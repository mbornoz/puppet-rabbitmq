# Class: rabbitmq::server
#
# This module manages the installation and config of the rabbitmq server
#   it has only been tested on certain version of debian-ish systems
# Parameters:
#  [*port*] - port where rabbitmq server is hosted
#  [*delete_guest_user*] - rather or not to delete the default user
#  [*version*] - version of rabbitmq-server to install
#  [*package_name*] - name of rabbitmq package
#  [*service_name*] - name of rabbitmq service
#  [*service_ensure*] - desired ensure state for service
#  [*stomp_port*] - port stomp should be listening on
#  [*node_ip_address*] - ip address for rabbitmq to bind to
#  [*config*] - contents of config file
#  [*env_config*] - contents of env-config file
#  [*config_cluster*] - whether to configure a RabbitMQ cluster
#  [*cluster_disk_nodes*] - which nodes to cluster with (including the current one)
#  [*erlang_cookie*] - erlang cookie, must be the same for all nodes in a cluster
#  [*wipe_db_on_cookie_change*] - whether to wipe the RabbitMQ data if the specified
#    erlang_cookie differs from the current one. This is a sad parameter: actually,
#    if the cookie indeed differs, then wiping the database is the *only* thing you
#    can do. You're only required to set this parameter to true as a sign that you
#    realise this.
#  [*default_user*] - The default user name
#  [*default_pass*] - The default password
#  [*ssl*] - whether to use SSL
#  [*ssl_port*] - the port used for SSL connections
#  [*ssl_cacert*] - the CA certificate for SSL connections
#  [*ssl_cert*] - the certificate for SSL connections
#  [*ssl_key*] - the private key for SSL connections
#  [*ssl_stomp_port*] - ssl port stomp should be listening on
#  [*ldap_auth*] - whether to use LDAP for authentication
#  [*ldap_server*] - the LDAP server to use for authentication
#  [*ldap_user_dn_pattern*] - the DN to use for user authentication with LDAP
#  [*ldap_use_ssl*] - whether to use SSL for LDAP authentication
#  [*ldap_port*] - the LDAP port to use
#  [*ldap_log*] - LDAP authentication log level
# Requires:
#  stdlib
# Sample Usage:
#
#
#
#
# [Remember: No empty lines between comments and class definition]
class rabbitmq::server(
  $port = '5672',
  $delete_guest_user = false,
  $package_name = 'rabbitmq-server',
  $version = 'UNSET',
  $service_name = 'rabbitmq-server',
  $service_ensure = 'running',
  $config_stomp = false,
  $stomp_port = '6163',
  $config_cluster = false,
  $cluster_disk_nodes = [],
  $node_ip_address = 'UNSET',
  $config='UNSET',
  $env_config='UNSET',
  $erlang_cookie='EOKOWXQREETZSHFNTPEY',
  $wipe_db_on_cookie_change=false,
  $default_user='guest',
  $default_pass='guest',
  $ssl=false,
  $ssl_port='5671',
  $ssl_cacert='',
  $ssl_cert='',
  $ssl_key='',
  $ssl_stomp_port='6164',
  $ldap_auth=false,
  $ldap_server='ldap',
  $ldap_user_dn_pattern='cn=${username},ou=People,dc=example,dc=com',
  $ldap_use_ssl=false,
  $ldap_port='389',
  $ldap_log=false,
) {

  validate_bool($delete_guest_user, $config_stomp)
  validate_re($port, '\d+')
  validate_re($stomp_port, '\d+')
  validate_re($ssl_stomp_port, '\d+')

  validate_bool($ldap_auth)
  validate_string($ldap_server)
  validate_string($ldap_user_dn_pattern)
  validate_bool($ldap_use_ssl)
  validate_re($ldap_port, '\d+')
  validate_bool($ldap_log)

  if ($ldap_auth) {
    rabbitmq_plugin { 'rabbitmq_auth_backend_ldap':
      ensure => present,
    }
  }

  if $version == 'UNSET' {
    $version_real = '2.4.1'
    $pkg_ensure_real   = 'present'
  } else {
    $version_real = $version
    $pkg_ensure_real   = $version
  }
  if $config == 'UNSET' {
    $config_real = template("${module_name}/rabbitmq.config")
  } else {
    $config_real = $config
  }
  if $env_config == 'UNSET' {
    $env_config_real = template("${module_name}/rabbitmq-env.conf.erb")
  } else {
    $env_config_real = $env_config
  }

  $plugin_dir = "/usr/lib/rabbitmq/lib/rabbitmq_server-${version_real}/plugins"

  package { $package_name:
    ensure => $pkg_ensure_real,
    notify => Class['rabbitmq::service'],
  }

  file { '/etc/rabbitmq':
    ensure  => directory,
    owner   => '0',
    group   => '0',
    mode    => '0644',
    require => Package[$package_name],
  }

  file { '/etc/rabbitmq/ssl':
    ensure  => directory,
    owner   => '0',
    group   => '0',
    mode    => '0644',
    require => Package[$package_name],
  }

  file { 'rabbitmq.config':
    ensure  => file,
    path    => '/etc/rabbitmq/rabbitmq.config',
    content => $config_real,
    owner   => '0',
    group   => '0',
    mode    => '0644',
    require => Package[$package_name],
    notify  => Class['rabbitmq::service'],
  }

  if $config_cluster {
    file { 'erlang_cookie':
      path =>"/var/lib/rabbitmq/.erlang.cookie",
      owner   => rabbitmq,
      group   => rabbitmq,
      mode    => '0400',
      content => $erlang_cookie,
      replace => true,
      before  => File['rabbitmq.config'],
      require => Exec['wipe_db'],
    }
    # require authorize_cookie_change

    if $wipe_db_on_cookie_change {
      exec { 'wipe_db':
        command => '/etc/init.d/rabbitmq-server stop; /bin/rm -rf /var/lib/rabbitmq/mnesia',
        require => Package[$package_name],
        unless  => "/bin/grep -qx ${erlang_cookie} /var/lib/rabbitmq/.erlang.cookie"
      }
    } else {
      exec { 'wipe_db':
        command => '/bin/false "Cookie must be changed but wipe_db is false"', # If the cookie doesn't match, just fail.
        require => Package[$package_name],
        unless  => "/bin/grep -qx ${erlang_cookie} /var/lib/rabbitmq/.erlang.cookie"
      }
    }
  }

  file { 'rabbitmq-env.config':
    ensure  => file,
    path    => '/etc/rabbitmq/rabbitmq-env.conf',
    content => $env_config_real,
    owner   => '0',
    group   => '0',
    mode    => '0644',
    notify  => Class['rabbitmq::service'],
  }

  class { 'rabbitmq::service':
    service_name => $service_name,
    ensure       => $service_ensure,
  }

  if $delete_guest_user {
    # delete the default guest user
    rabbitmq_user{ 'guest':
      ensure   => absent,
      provider => 'rabbitmqctl',
    }
  }

  rabbitmq_plugin { 'rabbitmq_management':
    ensure => present,
  }

  exec { 'Download rabbitmqadmin':
    command => "curl http://${default_user}:${default_pass}@localhost:5${port}/cli/rabbitmqadmin -o /var/tmp/rabbitmqadmin",
    creates => '/var/tmp/rabbitmqadmin',
    require => [
      Class['rabbitmq::service'],
      Rabbitmq_plugin['rabbitmq_management']
    ],
  }

  file { '/usr/local/bin/rabbitmqadmin':
    owner   => 'root',
    group   => 'root',
    source  => '/var/tmp/rabbitmqadmin',
    mode    => '0755',
    require => Exec['Download rabbitmqadmin'],
  }

}
