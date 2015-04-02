require 'chef/knife'
require 'knife-sharp/common'
require 'grit'

module KnifeSharp
  class SharpAlign < Chef::Knife
    include KnifeSharp::Common

    banner "knife sharp align BRANCH ENVIRONMENT [OPTS]"

    [:cookbooks, :databags, :roles].each do |opt|
      option opt,
        :short => "-#{opt.to_s[0,1].upcase}",
        :long => "--#{opt}-only",
        :description => "sync #{opt} only",
        :default => false
    end

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
      if config[:cookbooks] or config[:databags] or config[:roles]
        do_cookbooks, do_databags, do_roles = config[:cookbooks], config[:databags], config[:roles]
      else
        do_cookbooks, do_databags, do_roles = true, true, true
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

      # All questions asked, can we proceed ?
      if cookbooks_to_update.empty? and databags_to_update.empty? and roles_to_update.empty?
        ui.msg "Nothing else to do"
        exit 0
      end

      ui.confirm(ui.color("> Proceed ", :bold))
      sca.bump_cookbooks(environment, cookbooks_to_update) if do_cookbooks
      sda.update_databags(databags_to_update) if do_databags
      sra.update_roles(roles_to_update) if do_roles
    end
  end
end
