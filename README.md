# Knife sharp plugin

knife-sharp adds several handy features to knife, adapted to our workflow @ Fotolia.
Features:
* align : sync data bags, roles and cookbook versions between a local git branch and a chef server
* backup : dump environments, roles and data bags to local json files
* server : switch between chef servers using multiple knife.rb config files

# Tell me more

When you want an environment to reflect a given branch you have to check by hand (or using our consistency plugin), and some mistakes can be made.
This plugin aims to help to push the right version into an environment.

It also allows to adopt a review workflow for main chef components :
* Track data bags, roles (as JSON files) and cookbooks in your Chef git repository
* Push each modification of any to peer-review
* Once merged, upload every change with knife sharp align

# Show me !

## Align

<pre>
$ git branch
[...]
* ldap
master
[...]

$ knife environment show production
chef_type:            environment
cookbook_versions:
[...]
  apache:  0.0.6
  ldap:  0.0.3
[...]

$ knife sharp align ldap production
== Cookbooks ==
* ldap is not up-to-date (local: 0.0.4/remote: 0.0.3)
* apache is not up-to-date (local: 0.0.7/remote: 0.0.6)
> Update ldap cookbook to 0.0.4 on server ? Y/N/(A)ll/(Q)uit [N] y
> Update apache cookbook to 0.0.4 on server ? Y/N/(A)ll/(Q)uit [N] y
== Data bags ==
* infrastructure/services data bag item is not up-to-date
* Skipping infrastructure/services data bag (ignore list)
* Data bags are up-to-date.
== Roles ==
* Roles are up-to-date.
> Proceed ? (Y/N) y
* Uploading cookbook(s) ldap, apache
* Bumping ldap to 0.0.4 for environment production
* Bumping apache to 0.0.7 for environment production
</pre>

Then we can check environment :

<pre>
$ knife environment show production
chef_type:            environment
cookbook_versions:
[...]
  apache:  0.0.7
  ldap:  0.0.4
[...]

$ knife sharp align ldap production
== Cookbooks ==
* Environment production is up-to-date.
[...]
</pre>

Cookbooks, data_bags and roles are uploaded, and cookbook versions updated in given environment.

To use all of these features, your knife.rb(s) must provide paths for cookbooks, data bags and roles (see [configuration](#Configuration))

### Ignore list

In a "multi chef server" environment (e.g development/production), you might want to ignore some updates on a given chef server, for instance:
  * not uploading a test cookbook on your production server
  * not updating DNS domain with production's one on your dev server
  * avoid overriding data you are currently working on

Those items can be specified in sharp config file:
```yaml
prod: # chef server name, knife-prod.rb client config
  ignore_cookbooks: [ tests ]

dev:
  ignore_databags: [ infrastructure/dns ]
  ignore_roles: [ webserver ]
```

(more in [sharp-config](ext/sharp-config.yml))

### Downgrading cookbook versions

By default, `knife sharp align` will only try to upgrade cookbook (e.g local version > server version)
It is possible to allow downgrading using `--force-align` (`-f`) command line switch.

Example:
<pre>
knife sharp align master production -f
On server dev
== Cookbooks ==
* syslog is to be downgraded (local: 0.0.44/remote: 0.0.45)
* sudo is to be downgraded (local: 0.0.8/remote: 0.0.9)
[...]
</pre>

## Backup

Making a backup before a large change can be a lifesaver. Knife sharp can do it for you, easily
<pre>
$ knife sharp backup
Backing up roles
Backing up environments
Backing up databags
$
</pre>

All these items get stored in the place defined in your config file.

## Server

<pre>
$ knife sharp server
Available servers:
   prod (/home/jamiez/.chef/knife-prod.rb)
>> dev (/home/jamiez/.chef/knife-dev.rb)

$ knife sharp server prod
The knife configuration has been updated to use prod.

$ knife sharp server
Available servers:
>> prod (/home/jamiez/.chef/knife-prod.rb)
   dev (/home/jamiez/.chef/knife-dev.rb)
</pre>

## Rollback

Sometimes you need to be able to rollback a change quickly, because failure happens. So knife sharp now creates rollback points of environment constraints.

A picture says a thousand words :

<pre>
$ knife sharp rollback --list
Available rollback points :
  * 1370414322 (Wed Jun 05 08:38:42 +0200 2013)
  * 1370418655 (Wed Jun 05 09:50:55 +0200 2013)
  * 1370419966 (Wed Jun 05 10:12:46 +0200 2013)
  * 1370421569 (Wed Jun 05 10:39:29 +0200 2013)
$ knife sharp rollback --show 1370421569
Rollback point has the following informations :
  environment : production
  cookbooks versions :
   * tests => = 0.0.2
   * varnish => = 0.0.10
$ knife sharp rollback --to 1370421569
Rollback point has the following informations :
  environment : production
  cookbooks versions :
   * varnish => = 0.0.10
   * tests => = 0.0.2
Continue rollback ? Y/(N) [N] y
Setting varnish to version = 0.0.10
Setting tests to version = 0.0.2
</pre>

The activation of this rollback feature and its storage dir can be configured in your sharp-config.yml file.

# Configuration

Dependencies :
* grit

The plugin will search in 2 places for its config file :
* "/etc/sharp-config.yml"
* "~/.chef/sharp-config.yml"

An example config file is provided in ext/.

A working knife setup is also required (cookbook/role/data bag paths depending on the desired features).

Fully enabled Sharp needs:
```ruby
cookbook_path            '/home/jamiez/chef/cookbooks'
data_bag_path            '/home/jamiez/chef/data_bags'
role_path                '/home/jamiez/chef/roles'
```
in knife.rb

## Cookbooks path & git
If your cookbook_path is not the root of your git directory then the grit gem will produce an error. This can be circumvented by adding the following directive in your config file :

```yaml
global:
  git_cookbook_path: "/home/nico/sysadmin/chef/"
```

As we version more than the cookbooks in the repo.

## Logging
It's good to have things logged. The plugin can do it for you. Add this to your config file
```yaml
logging:
  enabled: true
  destination: "~/.chef/sharp.log"
```

It will log uploads, bumps and databags to the standard logger format.

# ZSH completion

want a completion on changing servers ?

```sh
alias kss="knife sharp server"

function knife_servers { reply=($(ls .chef/knife-*.rb | sed -r 's/.*knife-([a-zA-Z0-9]+)\.rb/\1/' )); }
compctl -K knife_servers kss
```

# Credits

The damn good knife spork plugin from the etsy folks : https://github.com/jonlives/knife-spork

Idea for knife sharp server comes from https://github.com/greenandsecure/knife-block

License
=======
3 clauses BSD

Authors
=======
* Nicolas Szalay | https://github.com/rottenbytes
* Jonathan Amiez | https://github.com/josqu4red

Contributors
============
* Grégoire Doumergue
