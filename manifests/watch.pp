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
) {
  include consul_template

  $concat_name = "consul-template/${instance_name}/config.json"

  # Check if consul service already exists.. if not, create it
  if !File["/lib/systemd/system/consul-template-{$instance_name}.service"] {
    file { "/lib/systemd/system/consul-template-{$instance_name}.service":
      mode    => '0644',
      owner   => 'root',
      group   => 'root',
      content => template('consul_template/consul-template.systemd.erb'),
    }

    service { "consul-template-{$instance_name}":
      ensure   => $consul_template::service_ensure,
      enable   => $consul_template::service_enable,
      provider => $service_provider,
      name     => "consul-template-{$instance_name}",
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
      notify => Service['consul-template-{$instance_name}'],
    }

    $config_base = {
      consul => 'localhost:8500',
    }
    $_config_hash = deep_merge(config_base, $consul_template::config_defaults, $consul_template::config_hash)

    # Using our parent module's pretty_config & pretty_config_indent just because
    $content_full = consul_template::sorted_json($_config_hash, $consul_template::pretty_config, $consul_template::pretty_config_indent)
    # remove the closing }
    $content = regsubst($content_full, '}$', '')

    concat::fragment { 'consul-service-pre':
      target  => $concat_name,
      # add the opening template array so that we can insert watch fragments
      content => "${content},\n    \"template\": [\n",
      order   => '1',
    }

    # Realizes concat::fragments from consul_template::watches that make up 1 or
    # more template configs.
    Concat::Fragment <| target == $concat_name |>

    concat::fragment { 'consul-service-post':
      target  => $concat_name,
      # close off the template array and the whole object
      content => "    ]\n}",
      order   => '99',
    }

    file { $consul_template::config_dir:
      ensure  => 'directory',
      purge   => true,
      recurse => true,
      owner   => $consul_template::user,
      group   => $consul_template::group,
      mode    => '0755',
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
    $source = "${consul_template::config_dir}/${name}.ctmpl"
    $config_source = {
      source => $source,
    }

    file { $source:
      ensure  => 'file',
      owner   => $consul_template::user,
      group   => $consul_template::group,
      mode    => $consul_template::config_mode,
      content => template($template),
      notify  => Service['consul-template'],
    }

    $frag_name = $source
    $fragment_requires = File[$source]
  }

  $config_hash_all = deep_merge($_config_hash, $config_source)
  $content_full = consul_template::sorted_json($config_hash_all, $consul_template::pretty_config, $consul_template::pretty_config_indent)
  $content = regsubst(regsubst($content_full, "}\n$", '}'), "\n", "\n    ", 'G')

  @concat::fragment { $frag_name:
    target  => 'consul-template/config.json',
    # NOTE: this will result in all watches having , after them in the JSON
    # array. That won't pass strict JSON parsing, but luckily HCL is fine with it.
    content => "      ${content},\n",
    order   => '50',
    notify  => Service['consul-template'],
    require => $fragment_requires,
  }
}
