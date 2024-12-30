class Kamal::Commands::Builder::Cloud < Kamal::Commands::Builder::Base
  # Tracks the type of build context
  attr_accessor :context_type

  def initialize(...)
    set_context_type
    super(...)
  end

  def create
    chain \
      (create_context if context_needed?),
      create_buildx
  end

  def create_context
    docker :context, :create, context_name, "--description", "'#{builder_name} host'", "--docker", "'host=#{remote}'"
  end

  def create_buildx
    docker :buildx, :create, "--name", builder_name, context_name
  end

  def inspect_builder
    docker :buildx, :inspect, builder_name
  end

  private

  def context_needed?
    # Raise error for invalid local paths
    raise Kamal::ConfigurationError, "Context is not a valid file or directory: #{context_name}" if @context_type == :invalid_local_path
    return false if @context_type == :local_file || @context_type == :local_directory
    true
  end

  def context_name
    builder_config.context
  end

  def builder_name
    if bln_cloud_builder_available
      str_cloud_builder_name
    else
      raise Kamal::ConfigurationError, "Missing cloud builder name for driver: #{driver}"
    end
  end

  # TODO: Remove dependency on `jq`
  def str_cloud_builder_name
    `docker builder ls --format "json" | jq -s 'map(select(.Driver == "cloud")) | map(.Name) | unique | first'`.strip!
    
  end

  def bln_cloud_builder_available
    `docker builder ls --format "json" | jq -s 'map(.Driver) | contains(["cloud"])'`.strip!
  end

  def set_context_type
    f = Pathname.new(context_name)

    @context_type = case
                    when standard_input?
                      # Context provided via standard input (e.g., piped content)
                      :docker_standard_input

                    when f.relative? || f.absolute?
                      # Local file system context
                      if f.directory?
                        :local_directory
                      elsif f.file?
                        :local_file
                      else
                        :invalid_local_path
                      end
                    when remote_resource?
                      # Remote resource context
                      classify_remote_resource
                    else
                      # Unrecognized context type
                      :unknown_context
                    end
  end

  def standard_input?
    context_name == '-' || context_name == '/dev/stdin'
  end

  def remote_resource?
    begin
      uri = URI.parse(context_name)
      uri.scheme && ['http', 'https', 'git', 'ftp'].include?(uri.scheme)
    rescue URI::InvalidURIError
      false
    end
  end

  def classify_remote_resource
    uri = URI.parse(context_name)

    case
    when git_repository?
      :git_repository
    when tarball?
      :remote_tarball
    when http_or_https_file?
      :remote_file
    else
      :unknown_remote_resource
    end
  end

  def git_repository?
    context_name.match?(/\.git$/) || 
    context_name.include?('github.com') || 
    context_name.include?('gitlab.com') || 
      context_name.include?('bitbucket.org')
  end

  def tarball?
    context_name.match?(/\.(tar|tar\.gz|tgz|tar\.bz2|zip)$/)
  end

  def http_or_https_file?
    uri = URI.parse(context_name)
    uri.scheme.in?(['http', 'https']) && 
      uri.path.match?(/\.[a-zA-Z0-9]+$/)
  end
end
