# apache2/manifests/classes/apache2_debian.pp
# by Sam Quigley <sq@wesabe.com>

# this class attempts to mimic the default configuration of the debian
# apache2 package

class apache2::debian inherits apache2 {
  apache2::config { "debian.conf":
    order => "000",
    ensure => present,
  }

  apache2::module { ["alias", "auth_basic", "authn_file", 
    "authz_default", "authz_groupfile", "authz_host", 
    "authz_user", "autoindex", "cgid", "dir", "env", "mime", 
    "negotiation", "setenvif", "status"]:
    ensure=> present,
  }
}
