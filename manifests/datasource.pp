# creates database on mysql server. creates config files and database tables on biserver.
define pentaho::datasource($type = 'mysql', $driver = 'com.mysql.jdbc.Driver', $username, $password, $tables_schema) {
  Class['pentaho::config'] -> Pentaho::Datasource[$title]

  Exec {
    path => [ '/usr/local/bin', '/usr/bin', '/bin' ]
  }

  # FIXME: this should only depend on tags within the module
  if tagged('biserver') {
    $schema_file = md5($tables_schema)
    $schema_path = "/opt/pentaho/biserver-ce/data/puppet/${schema_file}"
    file { $schema_path:
      owner   => 'puppet',
      mode    => '600',
      ensure  => file,
      source  => $tables_schema
    }
    exec { "create $title schema":
      command => "mysql -h ${pentaho::config::database_host} -u${username} -p${password} ${title} < ${schema_path}",
      refreshonly => true,
      subscribe => [File[$schema_path], Exec['import hibernate']],
    }

    $url = "jdbc:${type}://${pentaho::config::database_host}:${pentaho::config::database_port}/${title}"
    # creates a file containing sql to populate datasource record, then execs mysql client
    $sql_tmpl = "<% require 'base64' %>REPLACE INTO `DATASOURCE` (`NAME`, `DRIVERCLASS`, `USERNAME`, `PASSWORD`, `URL`)
      VALUES ('${title}', '${driver}', '${username}', '<%= Base64.encode64(\"${password}\").strip -%>', '${url}');"
    $sql = inline_template($sql_tmpl)
    $sql_file = md5($sql)
    $sql_path = "/opt/pentaho/biserver-ce/data/puppet/${sql_file}"

    file { "${sql_path}":
      owner   => 'puppet',
      mode    => '600',
      content => $sql,
    }
    exec { "create datasource $title":
      command => "mysql -h ${pentaho::config::database_host} -u${pentaho::config::hibernate_user} -p${pentaho::config::hibernate_password} ${pentaho::config::hibernate_database} < ${sql_path}",
      refreshonly => true,
      subscribe => File[$sql_path]
    }
  } 
  if tagged('mysqlserver') {
    Class['pentaho::database'] -> Pentaho::Datasource[$title]
    mysql::db { $title:
      user     => $username,
      password => $password,
      # TODO: restrict hosts
      host     => '%',
      grant    => ['all'],
      before   => tagged('biserver') ? { true => Exec["create $title schema"], default => undef }
    }
  }
}