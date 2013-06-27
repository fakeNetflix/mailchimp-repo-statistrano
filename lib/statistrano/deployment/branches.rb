module Statistrano
  module Deployment

    #
    # Branches is for deployments that depend upon the
    # current git branch, eg. doing feature branch deployments
    #
    class Branches < Base

      #
      # Config holds all deployment configuration details
      #
      class Config < Base::Config
        attr_accessor :public_dir
        attr_accessor :manifest
        attr_accessor :base_domain

        def initialize
          yield(self) if block_given?
        end

        def tasks
          super.merge({
            :list => { method: :list_releases, desc: "List branches" },
            :prune => { method: :prune_releases, desc: "Prune an branch" },
            :generate_index => { method: :generate_index, desc: "Generate branches index" }
          })
        end
      end

      def initialize name
        @name = name
        @config = Config.new do |config|
          config.public_dir = Git.current_branch.to_slug
          config.post_deploy_task = "#{@name}:generate_index"
        end
        RakeTasks.register(self)
      end

      # define certain things that an action
      # depends on
      # @return [Void]
      def prepare_for_action
        super
      end

      # output a list of the releases in manifest
      # @return [Void]
      def list_releases
        @manifest.releases.each do |release|
          LOG.msg "#{release.name} created at #{Time.at(release.time).strftime('%a %b %d, %Y at %l:%M %P')}"
        end
      end

      # trim releases not in the manifest,
      # get user input for removal of other releases
      # @return [Void]
      def prune_releases
        prune_untracked_releases

        if get_releases && get_releases.length > 0

          picked_release = pick_release_to_remove
          if picked_release
            remove_release(picked_release)
            generate_index
          else
            LOG.warn "sorry, that isn't one of the releases"
          end

        else
          LOG.warn "no releases to prune"
        end
      end

      # generate an index file for releases in the manifest
      # @return [Void]
      def generate_index
        index_dir = File.join( @config.remote_dir, "index" )
        index_path = File.join( index_dir, "index.html" )
        setup_release_path( index_dir )
        @ssh.run_command "touch #{index_path} && echo '#{release_list_html}' > #{index_path}"
      end

      private

        def pick_release_to_remove
          list_releases_with_index

          picked_release = Shell.get_input("select a release to remove: ").gsub(/[^0-9]/, '')

          if !picked_release.empty? && picked_release.to_i < get_releases.length
            return get_releases[picked_release.to_i]
          else
            return false
          end
        end

        def list_releases_with_index
          get_releases.each_with_index do |release,idx|
            LOG.msg "#{release}", "[#{idx}]", :blue
          end
        end

        # removes releases that are on the remote but not in the manifest
        # @return [Void]
        def prune_untracked_releases
          get_actual_releases.each do |release|
            remove_release(release) unless get_releases.include? release
          end
        end

        def release_list_html
          release_list = @manifest.releases.map { |release| release_as_li(release) }.join('')
          template = IO.read( File.expand_path( '../../../../templates/index.html', __FILE__) )
          template.gsub( '{{release_list}}', release_list )
        end

        def release_as_li release
          "<li>" +
          "<a href=\"http://#{release.name}.#{@config.base_domain}\">#{release.name}</a>" +
          "<small>updated: #{Time.at(release.time).strftime('%A %b %d, %Y at %l:%M %P')}</small>" +
          "</li>"
        end

        def setup
          super
          @manifest = Manifest.new( @config, @ssh )
        end

        # send code to remote server
        # @return [Void]
        def create_release
          setup_release_path(current_release_path)
          rsync_to_remote(current_release_path)

          @manifest.add_release( Manifest::Release.new( @config.public_dir ) )

          LOG.msg "Created release at #{@config.public_dir}"
        end

        # remove a release
        # @param name [String]
        # @return [Void]
        def remove_release name
          LOG.msg "Removing release '#{name}'"
          @ssh.run_command "rm -rf #{release_path(name)}"
          @manifest.remove_release(name)
        end

        # return array of releases from the manifest
        # @return [Array]
        def get_releases
          @manifest.list
        end

        # return array of releases on the remote
        # @return [Array]
        def get_actual_releases
          releases = []
          @ssh.run_command("ls -mp #{@config.remote_dir}") do |ch, stream, data|
            releases = data.strip.split(',')
          end
          releases.keep_if { |release| /\/$/.match(release) }
          releases.map { |release| release.strip.gsub(/(\/$)/, '') }.keep_if { |release| release != "index" }
        end

        # path to the current release
        # this is based on the git branch
        # @return [String]
        def current_release_path
          File.join( @config.remote_dir, @config.public_dir )
        end

        # path to a specific release
        # @return [String]
        def release_path name
          File.join( @config.remote_dir, name )
        end

    end

  end
end