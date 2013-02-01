# Knife sharp plugin

knife-sharp adds several handy features to knife, adapted to our workflow @ Fotolia.
Features:
* align : sync data bags, roles and cookbook versions between a local git branches and a chef server
* backup : dump environments, roles and data bags to local json files
* server : switch between chef servers using multiple knife.rb config files

# Tell me more

When you want an environment to reflect a given branch you have to check by hand (or using our consistency plugin), and some mistakes can be made. This plugin aims to help to push the right version into an environment.

It also allows to adopt a review workflow for main chef components :
* Track data bags, roles (as JSON files) and cookbooks in your Chef git repository
* Push each modification of any to peer-review
* Once merged, upload every change with knife sharp align

# Show me !

## Align

<pre>
$ git branch
...
master
* syslog_double
...
$ knife environment show sandboxnico
chef_type:            environment
cookbook_versions:
...
  syslog:  0.0.16
...
$ knife sharp align syslog_double sandboxnico

Will change in environment sandboxnico :
* syslog gets version 0.0.17
Upload and set version into environment sandboxnico ? Y/N
Y
Successfull upload for syslog
Aligning 1 cookbooks
Aligning data bags
* infrastructure/mail data bag item is not up-to-date
Update infrastructure/mail data bag item on server ? Y/N/(A)ll/(Q)uit [N] n
* Skipping infrastructure/mail data bag item
Aligning roles
* Dev_Server role is not up-to-date (run list)
Update Dev_Server role on server ? Y/N/(A)ll/(Q)uit [N] n
* Skipping Dev_Server role
</pre>

Then we can check environment :

<pre>
$ knife environment show sandboxnico
chef_type:            environment
cookbook_versions:
...
  syslog:  0.0.17
...
$ knife sharp align syslog_double sandboxnico
Nothing to do : sandboxnico has same versions as syslog_double
</pre>

It will upload the cookbooks (to ensure they meet the one on the branch you're working on) and will set the version to the required number.

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

# Configuration

Dependencies :
* grit

The plugin will search in 2 places for its config file :
* "/etc/sharp-config.yml"
* "~/.chef/sharp-config.yml"

An example config file is provided in ext/.

A working knife setup is also required (cookbook/role/data bag paths depending on the desired features)

## Cookbooks path & git
If your cookbook_path is not the root of your git directory then the grit gem will produce an error. This can be circumvented by adding the following directive in your config file :

<pre>
global:
  git_cookbook_path: "/home/nico/sysadmin/chef/"
</pre>

As we version more than the cookbooks in the repo.

## Logging
It's good to have things logged. The plugin can do it for you. Add this to your config file
<pre>
logging:
  enabled: true
  destination: "~/.chef/sharp.log"
</pre>

It will log uploads, bumps and databags to the standard logger format.

# Credits

The damn good knife spork plugin from the etsy folks : https://github.com/jonlives/knife-spork

Idea for knife sharp server comes from https://github.com/greenandsecure/knife-block

License
=======
3 clauses BSD

Authors
======
Nicolas Szalay | https://github.com/rottenbytes
Jonathan Amiez | https://github.com/josqu4red
