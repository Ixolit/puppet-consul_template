# == Class consul_template::intall
#
class consul_template::install {

  if ! empty($consul_template::data_dir) {
    file { $consul_template::data_dir:
      ensure => 'directory',
      owner  => $consul_template::user,
      group  => $consul_template::group,
      purge   => true,
      recurse => true,
      mode   => '0755',
    }
  }

  if $consul_template::install_method == 'url' {

    include staging
    if $facts['os']['name'] != 'darwin' {
      ensure_packages(['tar'])
    }
    staging::file { "consul-template_${consul_template::version}.${consul_template::download_extension}":
      source => $consul_template::_download_url,
    }
    -> file { "${staging::path}/consul-template-${consul_template::version}":
      ensure => directory,
    }
    -> staging::extract { "consul-template_${consul_template::version}.${consul_template::download_extension}":
      target  => "${staging::path}/consul-template-${consul_template::version}",
      creates => "${staging::path}/consul-template-${consul_template::version}/consul-template",
    }
    -> file {
      "${staging::path}/consul-template-${consul_template::version}/consul-template":
        owner => 'root',
        group => 0, # 0 instead of root because OS X uses "wheel".
        mode  => '0555';
      "${consul_template::bin_dir}/consul-template":
        ensure => link,
        target => "${staging::path}/consul-template-${consul_template::version}/consul-template";
    }

  } elsif $consul_template::install_method == 'package' {

    package { $consul_template::package_name:
      ensure => $consul_template::package_ensure,
    }

  } else {
    fail("The provided install method ${consul_template::install_method} is invalid")
  }


  if $consul_template::manage_user {
    user { $consul_template::user:
      ensure => 'present',
      system => true,
    }
  }
  if $consul_template::manage_group {
    group { $consul_template::group:
      ensure => 'present',
      system => true,
    }
  }
}
