# == Definition consul_template::watch
#
# This definition is called from consul_template
# This is a single instance of a configuration file to watch
# for changes in Consul and update the local file
define consul_template::watch (
  $instance_name    = 'main',
  $config_hash     = {},
  $config_defaults = {},
  $template        = undef,
  $template_vars   = {},
  $apparmor_profile = undef
) {
  include consul_template

  $concat_name = "consul-template/${instance_name}/config.json"

  if $apparmor_profile {
    apparmor::profile_inject { "consultemplate_watch-${name}":
      program_name => $apparmor_profile,
      content      => @("EOF");
        ${config_hash['destination']} r,
        |EOF
    }
  }
  
  $dirname = dirname($config_hash['destination'])
  apparmor::profile_inject {"consultemplate_write_${name}":
    program_name => "consul-template",
    content      => @("EOF");
      # tmpfile created by consul-template before the destination file will be overwritten
      ${dirname}/[0-9][0-9][0-9]* rw,
      ${config_hash['destination']} rw,
      |EOF
  }

  # Check if consul instance already exists.. if not, create it
  if !defined(File["/lib/systemd/system/consul-template-${instance_name}.service"]) {
    file { "/lib/systemd/system/consul-template-${instance_name}.service":
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      content => template('consul_template/consul-template.systemd.erb'),
    }

    service { "consul-template-${instance_name}":
      ensure   => $consul_template::service_ensure,
      enable   => $consul_template::service_enable,
      name     => "consul-template-${instance_name}",
    }

    file { ["${consul_template::config_dir}/${instance_name}", "${consul_template::config_dir}/${instance_name}/config"]:
      ensure  => 'directory',
      purge   => true,
      recurse => true,
      owner   => $consul_template::user,
      group   => $consul_template::group,
      mode    => '0755',
    }
    -> concat { $concat_name:
      path   => "${consul_template::config_dir}/${instance_name}/config/config.json",
      owner  => $consul_template::user,
      group  => $consul_template::group,
      mode   => $consul_template::config_mode,
      notify => Service["consul-template-${instance_name}"],
    }

    $config_base = {
      consul => 'localhost:8500',
    }
    $_config_main_hash = deep_merge($config_base, $consul_template::config_defaults, $consul_template::config_hash)

    # Using our parent module's pretty_config & pretty_config_indent just because
    $content_main_full = consul_template::sorted_json($_config_main_hash, $consul_template::pretty_config, $consul_template::pretty_config_indent)
    # remove the closing }
    $content_main = regsubst($content_main_full, '}$', '')

    concat::fragment { "consul-service-pre-${instance_name}":
      target  => $concat_name,
      # add the opening template array so that we can insert watch fragments
      content => "${content_main},\n    \"template\": [\n",
      order   => '1',
    }

    # Realizes concat::fragments from consul_template::watches that make up 1 or
    # more template configs.
    Concat::Fragment <| target == $concat_name |>

    concat::fragment { "consul-service-post-${instance_name}":
      target  => $concat_name,
      # close off the template array and the whole object
      content => "    ]\n}",
      order   => '99',
    }
  }

  $_config_hash = deep_merge($config_defaults, $config_hash)
  if $template == undef and $_config_hash['source'] == undef {
    err ('Specify either template parameter or config_hash["source"] for consul_template::watch')
  }

  if $template != undef and $_config_hash['source'] != undef {
    err ('Specify either template parameter or config_hash["source"] for consul_template::watch - but not both')
  }

  unless $template {
    # source is specified in config_hash
    $config_source = {}
    $frag_name = $_config_hash['source']
    $fragment_requires = undef
  } else {
    # source is specified as a template
    $source = "${consul_template::config_dir}/${instance_name}/${name}.ctmpl"
    $config_source = {
      source => $source,
    }

    file { $source:
      ensure  => 'file',
      owner   => $consul_template::user,
      group   => $consul_template::group,
      mode    => $consul_template::config_mode,
      content => template($template),
      notify  => Service["consul-template-${instance_name}"],
    }

    $frag_name = $source
    $fragment_requires = File[$source]
  }

  $config_hash_all = deep_merge($_config_hash, $config_source)
  $content_full = consul_template::sorted_json($config_hash_all, $consul_template::pretty_config, $consul_template::pretty_config_indent)
  $content = regsubst(regsubst($content_full, "}\n$", '}'), "\n", "\n    ", 'G')

  @concat::fragment { $frag_name:
    target  => $concat_name,
    # NOTE: this will result in all watches having , after them in the JSON
    # array. That won't pass strict JSON parsing, but luckily HCL is fine with it.
    content => "      ${content},\n",
    order   => '50',
    notify  => Service["consul-template-${instance_name}"],
    require => $fragment_requires,
  }
}
