require 'chef/knife'
require 'knife-sharp/common'

module KnifeSharp
  class SharpAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp align BRANCH ENVIRONMENT [OPTS]"

    option :cookbooks,
      :short => "-C",
      :long => "--cookbooks-only",
      :description => "sync cookbooks only",
      :default => false

    option :roles,
      :short => "-R",
      :long => "--roles-only",
      :description => "sync roles only",
      :default => false

    option :databags,
      :short => "-D",
      :long => "--databags-only",
      :description => "sync data bags only",
      :default => false

    option :environments,
      :short => "-N",
      :long => "--environments-only",
      :description => "sync environments only",
      :default => false

    option :force_align,
      :short => "-f",
      :long => "--force-align",
      :description => "force local cookbook versions, allow downgrade",
      :default => false

    option :dump_remote_only,
      :short => "-B",
      :long => "--dump-remote-only",
      :description => "dump items not present locally (roles/databags)",
      :default => false

    def run
      # Checking args
      ensure_branch_and_environment_provided!

      # Checking repo branch
      ensure_correct_branch_provided!

      # check cli flags
      if config[:cookbooks] or config[:databags] or config[:roles] or config[:environments]
        do_cookbooks, do_databags, do_roles, do_environments = config[:cookbooks], config[:databags], config[:roles], config[:environments]
      else
        do_cookbooks, do_databags, do_roles, do_environments = true, true, true, true
      end

      ui.msg(ui.color("On server #{chef_server}", :bold)) if chef_server

      SharpCookbookAlign.load_deps
      sca = SharpCookbookAlign.new
      cookbooks_to_update = do_cookbooks ? sca.check_cookbooks(environment) : []
      SharpDataBagAlign.load_deps
      sda = SharpDataBagAlign.new
      databags_to_update = do_databags ? sda.check_databags : {}
      SharpRoleAlign.load_deps
      sra = SharpRoleAlign.new
      roles_to_update = do_roles ? sra.check_roles : {}
      SharpEnvironmentAlign.load_deps
      sea = SharpEnvironmentAlign.new
      environments_to_update = do_environments ? sea.check_environments : {}

      # All questions asked, can we proceed ?
      if cookbooks_to_update.empty? and databags_to_update.empty? and roles_to_update.empty? and environments_to_update.empty?
        ui.msg "Nothing else to do"
        exit 0
      end

      ui.confirm(ui.color("> Proceed ", :bold))
      sca.bump_cookbooks(environment, cookbooks_to_update) if do_cookbooks
      sda.update_databags(databags_to_update) if do_databags
      sra.update_roles(roles_to_update) if do_roles
      sea.update_environments(environments_to_update) if do_environments
    end
  end
end
