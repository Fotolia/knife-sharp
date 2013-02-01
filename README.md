# Knife sharp plugin

This plugin is used to align an environment cookbooks on a given git branch.
It can be used to synchronize data bags and roles from local JSON copy to Chef server.

# Tell me more

When you want an environment to reflect a given branch you have to check by hand (or using our consistency plugin), and some mistakes can be made. This plugin aims to help to push the right version into an environment.

It also allows to adopt a review workflow for main chef components :
* Track data bags, roles (as JSON files) and cookbooks in your Chef git repository
* Push each modification of any to peer-review
* Once merged, upload every change with knife sharp align

# Show me !

<pre>
[mordor:~] git branch
...
master
* syslog_double
...
[mordor:~] knife environment show sandboxnico
chef_type:            environment
cookbook_versions:
...
  syslog:  0.0.16
...
[mordor:~] knife sharp align syslog_double sandboxnico

Will change in environment sandboxnico :
* syslog gets version 0.0.17
Upload and set version into environment sandboxnico ? Y/N
Y
Successfull upload for syslog
Aligning 1 cookbooks
Done.
</pre>

Then we can check environment :

<pre>
[mordor:~] knife environment show sandboxnico
chef_type:            environment
cookbook_versions:
...
  syslog:  0.0.17
...
[mordor:~] knife sharp align syslog_double sandboxnico
Nothing to do : sandboxnico has same versions as syslog_double
</pre>

It will upload the cookbooks (to ensure they meet the one on the branch you're working on) and will set the version to the required number.

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

## Backups
Making a backup before a large change can be a lifesaver. Knife sharp can do it for you, easily
<pre>
$ knife sharp backup
Backing up roles
Backing up environments
Backing up databags
$
</pre>

All these items get stored in the place defined in your config file.

# See also
The damn good knife spork plugin from the etsy folks : https://github.com/jonlives/knife-spork

License
=======
3 clauses BSD

Authors
======
Nicolas Szalay | https://github.com/rottenbytes
Jonathan Amiez | https://github.com/josqu4red
