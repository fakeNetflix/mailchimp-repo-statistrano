module Statistrano
  module Deployment
    module Strategy

      # deployment type for running a releases deployment
      # accross multiple remotes
      #
      # @example:
      #
      #   define_deployment "multi", :multi_target do
      #     build_task 'deploy:build'
      #     local_dir  'build'
      #     remote_dir '/var/www/proj'
      #
      #     check_git  true
      #     git_branch 'master'
      #
      #     targets [
      #       { remote: 'web01' },
      #       { remote: 'web02' }
      #     ]
      #
      #     # each target gets merged with the global
      #     # configs and deployed to individually
      #     #
      #   end
      #
      class MultiTarget
        extend Deployment::Registerable
        extend Config::Configurable
        include InvokeTasks
        include CheckGit

        register_strategy :multi_target

        options :remote_dir, :local_dir,
                :remote, :user, :password, :keys, :forward_agent,
                :build_task, :post_deploy_task,
                :check_git, :git_branch, :repo_url

        option :release_count, 5
        option :release_dir, "releases"
        option :public_dir,  "current"

        option  :targets, []

        def initialize name
          @name = name
        end

        def targets
          return @_targets if @_targets

          options = config.options.dup
          targets = options.delete(:targets).map do |t|
                      options.merge(t)
                    end

          @_targets = targets.map do |t|
                        Remote.new(t)
                      end
        end

        def deploy
          unless safe_to_deploy?
            Log.error "exiting due to git check failing"
            abort()
          end

          build_data = invoke_build_task
          if build_data.respond_to? :to_hash
            build_data = build_data.to_hash
          else
            build_data = {}
          end

          targets.each do |t|
            releaser.create_release t, build_data
          end

          invoke_post_deploy_task
        end

        def rollback_release
          targets.each do |t|
            releaser.rollback_release t
          end
        end

        def prune_releases
          targets.each do |t|
            releaser.prune_releases t
          end
        end

        def list_releases
          targets.each do |t,out|
            releases = releaser.list_releases(t).map { |rel| rel[:release] }
            Log.info :"#{t.config.remote}", releases
          end
        end

        private

          def releaser
            ::Statistrano::Deployment::Releaser::Revisions.new config.options
          end

      end

    end
  end
end

require_relative 'multi_target/manifest'
