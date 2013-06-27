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
        releases = get_releases

        get_actual_releases.each do |release|
          remove_release(release) unless releases.include? release
        end

        if releases && releases.length > 0

          releases.each_with_index do |release,idx|
            LOG.msg "#{release}", "[#{idx}]", :blue
          end

          print "select a release to remove: "
          input = Shell.get_input.gsub(/[^0-9]/, '')
          release_to_remove = ( input != "" ) ? input.to_i : nil

          if (0..(releases.length-1)).to_a.include?(release_to_remove)
            remove_release( get_releases[release_to_remove] )
            generate_index
          else
            LOG.warn "sorry that isn't one of the releases"
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

        rs = ""
        @manifest.releases.each do |release|
          rs << "<li>"
          rs << "<a href=\"http://#{release.name}.#{@config.base_domain}\">#{release.name}</a>"
          rs << "<small>updated: #{Time.at(release.time).strftime('%A %b %d, %Y at %l:%M %P')}</small>"
          rs << "</li>"
        end
        template = IO.read( File.expand_path( '../../../../templates/index.html', __FILE__) )
        template.gsub!( '{{release_list}}', rs )

        cmd = "touch #{index_path} && echo '#{template}' > #{index_path}"
        setup_release_path( index_dir )
        @ssh.run_command cmd
      end

      private

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