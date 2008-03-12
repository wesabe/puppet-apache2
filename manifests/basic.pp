# apache2/manifests/classes/apache2_basic.pp
# by Sam Quigley <sq@wesabe.com>

# implements a basic, no-frills apache.  

class apache2::basic inherits apache2 {
  apache2::config { "base":
    order => "000",
    ensure => present,
    content => template("apache2/base.conf.erb"),
  }
  apache2::module { "dir": ensure => present } # provides DirectoryIndex

  apache2::config { "mpm":
    order => "010",
    ensure => present,
    content => template("apache2/mpm-$real_apache2_mpm.conf.erb"),
  }

  apache2::config { "mime":
    order => "020",
    ensure => present,
    content => template("apache2/mime-minimal.conf.erb"),
  }
  apache2::module { "mime": ensure => present }

  apache2::config { "browser_fixes":
    order => "030",
    ensure => present,
    content => template("apache2/browser_fixes.conf.erb"),
  }
  apache2::module { "setenvif": ensure => present }
  
}
