# apache2 module for puppet
# by Sam Quigley <sq@wesabe.com>
#
# based in part on code by Tim Stoop <tim.stoop@gmail.com> and 
# David Schmitt <david@schmitt.edv-bus.at>

# this file defines the base apache2 class, and does most of the heavy
# lifting.  see the other subclasses for friendlier versions.

# note: this code is currently very deb/ubuntu-specific
$apache_sites = "/etc/apache2/sites"
$apache_includes = "/etc/apache2/site-includes"
$apache_mods = "/etc/apache2/mods"
$apache_conf = "/etc/apache2/conf.d"

class apache2 {
  $real_apache2_mpm = $apache2_mpm ? { '' => 'worker', default => $apache2_mpm }
  
  case $real_apache2_mpm {
    'event': {
      package { "apache2-mpm-event": 
        ensure => installed,
        alias => apache2_mpm_provider
      }
      package { ["apache2-mpm-perchild", "apache2-mpm-prefork",
        "apache2-mpm-worker"]:
        ensure => absent,
      }
    }
    
    'prefork': {
      package { "apache2-mpm-prefork": 
        ensure => installed,
        alias => apache2_mpm_provider
      }
      package { ["apache2-mpm-event", "apache2-mpm-perchild",
        "apache2-mpm-worker"]:
        ensure => absent,
      }
    }

    'worker': {
      package { "apache2-mpm-worker": 
        ensure => installed,
        alias => apache2_mpm_provider
      }
      package { ["apache2-mpm-event", "apache2-mpm-perchild",
        "apache2-mpm-prefork"]:
        ensure => absent,
      }
    }
  }
	package { apache2:
		ensure => installed,
	  require => Package[apache2_mpm_provider],
	}

	service { apache2:
		ensure => running,
		pattern => "/usr/sbin/apache2",
		hasrestart => true,
		require => Package[apache2]
	}

  # using checksum => mtime and notify ensures that any changes to this dir 
  # will result in an apache reload
	file { $apache_conf:
		ensure => directory, checksum => mtime,
		mode => 644, owner => root, group => root,
		require => Package[apache2],
		notify => Exec["reload-apache2"];
	}

  # as above
	file { $apache_includes:
		ensure => directory, checksum => mtime,
		mode => 644, owner => root, group => root,
		require => Package[apache2],
		notify => Exec["reload-apache2"];
	}
	
	# this overwrites the default distro config with one that just includes
	# $apache_conf and friends
	file { "/etc/apache2/apache2.conf":
	  ensure => present,
	  mode => 644,
	  owner => root,
	  group => root,
	  source => "puppet://$servername/apache2/apache2.conf",
	  require => File[$apache_conf],
	}

  # nuke the package-provided ports.conf
  file {"/etc/apache2/ports.conf": ensure => absent }

  # make sure the default site isn't present.
	exec { "/usr/sbin/a2dissite default":
		onlyif => "/usr/bin/test -L /etc/apache2/sites-enabled/000-default",
		notify => Exec["reload-apache2"],
	}

	# Notify this when apache needs a reload. This is only needed when
	# sites are added or removed, since a full restart then would be
	# a waste of time. When the module-config changes, a force-reload is
	# needed.
	exec { "reload-apache2":
		command => "/etc/init.d/apache2 reload",
		refreshonly => true,
		before => [ Service["apache2"], Exec["force-reload-apache2"] ]
	}

	exec { "force-reload-apache2":
		command => "/etc/init.d/apache2 force-reload",
		refreshonly => true,
		before => Service["apache2"],
	}
	
  # Define an apache2 config snippet. Places all config snippets into
  # /etc/apache2/conf.d, where they will be automatically loaded
	define config ( $ensure = 'present', $content = '', $order="500") {
	  $real_content = $content ? { '' => template("apache2/${name}.conf.erb"), 
	    default => $content,
	  }
	  
	  file { "${apache_conf}/${order}-${name}.conf":
      ensure => $ensure,
      content => $content,
      mode => 644,
  	  owner => root,
  	  group => root,
		# given the way File[$apache_conf] is defined, this might lead to 
		# multiple restarts.  not sure.
			notify => Exec["reload-apache2"], 
    }
	}
  

  # Define an apache2 site. Place all site configs into
  # /etc/apache2/sites-available and en-/disable them with this type.
  #
  # You can add a custom require (string) if the site depends on packages
  # that aren't part of the default apache2 package. Because of the
  # package dependencies, apache2 will automagically be included.
  define site ( $ensure = 'present', $content = '' ) {
  	case $ensure {
  		'present' : {
        apache2::install_site { $name:
          content => $content
        }
  		}
  		'installed' : {
        apache2::install_site { $name:
          content => $content
        }
  		}
  		'absent' : {
  			exec { "/usr/sbin/a2dissite $name":
  				onlyif => "/bin/sh -c '[ -L ${apache_sites}-enabled/$name ] \\
  							&& [ ${apache_sites}-enabled/$name -ef ${apache_sites}-available/$name ]'",
  				notify => Exec["reload-apache2"],
  				require => Package["apache2"],
  			}
  		}
  		default: { err ( "Unknown ensure value: '$ensure'" ) }
  	}
  }

  # helper method to actually install a site -- called by site()
  define install_site ($content = '' ) {
	  # first, make sure the site config exists
    case $content {
      '': {
        file { "${apache_sites}-available/${name}":
          mode => 644,
      	  owner => root,
      	  group => root,
    	    ensure => present,
    	    alias => "site-$name",
        }
      }

      default: {
    	  file { "${apache_sites}-available/${name}":
          content => $content,
          mode => 644,
      	  owner => root,
      	  group => root,
  	      ensure => present,
  	      alias => "site-$name",  
        }        
      }
    }
	  
	  # now, enable it.
		exec { "/usr/sbin/a2ensite $name":
			unless => "/bin/sh -c '[ -L ${apache_sites}-enabled/$name ] \\
						&& [ ${apache_sites}-enabled/$name -ef ${apache_sites}-available/$name ]'",
			notify => Exec["reload-apache2"],
			require => File["site-$name"],
		}
	}

  # Define a site config fragment
  define site_include ( $ensure = 'present', $content = '' ) {
	  file { "${apache_includes}/${name}.inc":
      content => $content,
      mode => 644,
  	  owner => root,
  	  group => root,
      ensure => $ensure,
      require => File[$apache_includes],
    }    
  }

  # Define an apache2 module. Debian packages place the module config
  # into /etc/apache2/mods-available.
  #
  # You can add a custom require (string) if the module depends on 
  # packages that aren't part of the default apache2 package. Because of 
  # the package dependencies, apache2 will automagically be included.
  #
  # REVIEW: 20070901 <sq@wesabe.com> -- when facts can be distributed 
  # within modules (see puppet trac ticket #803), the unless/onlyif clauses
  # below should get rewritten to use custom facter facts
  define module ( $ensure = 'present') {
  	case $ensure {
  		'present' : {
  			exec { "/usr/sbin/a2enmod $name":
  				unless => "/bin/sh -c '[ -L ${apache_mods}-enabled/${name}.load ] \\
  					&& [ ${apache_mods}-enabled/${name}.load -ef ${apache_mods}-available/${name}.load ]'",
  				notify => Exec["force-reload-apache2"],
  			}
  		}
  		'absent': {
  			exec { "/usr/sbin/a2dismod $name":
  				onlyif => "/bin/sh -c '[ -L ${apache_mods}-enabled/${name}.load ] \\
  					&& [ ${apache_mods}-enabled/${name}.load -ef ${apache_mods}-available/${name}.load ]'",
  				notify => Exec["force-reload-apache2"],
  			}
  		}
  		default: { err ( "Unknown ensure value: '$ensure'" ) }
  	}
  }
}
