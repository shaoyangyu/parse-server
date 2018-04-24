# coding: utf-8
# frozen_string_literal: true

require 'thor'
class Hammer < Thor
  include Thor::Actions
  source_root '.'
end

class Hash
  def method_missing(methodname, *params)
    if self.class == Hash
      self[methodname]||self[methodname.to_s]
    else
      super
    end
  end
end

namespace :docker do
  config = JSON.parse(File.read('docker/dockerconfig.json'))

  TAG = ENV['TAG'] || 'latest'
  debug_yml = ENV['DEBUG_YAML'] || config.debug_yml
  prod_yml = ENV['PROD_YAML'] || config.prod_yml
  docker_repo = ENV['DOCKER_REPO'] || config.docker_repo
  task :bash, [:service] do |_t, args|
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} exec #{args[:service] || config.service_name} #{config.shell_command}")
  end

  desc 'destroy all services container'
  task :down do |_t, _args|
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} down")
  end

  desc 'run test with docker'
  task test: :up do
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} exec #{config.service_name} #{config.test_command}")
  end

  desc 'run rspec with docker'
  task rspec: :test do
  end

  desc 'start service with docker with prod env'
  task :run do
    exec_cmd("TAG=#{TAG} dockese -f #{prod_yml} up  -d")
  end

  desc 'start service with docker in debug mode '
  task :up do
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} up  -d")
  end

  desc 'debug service with docker '
  task debug: :up do
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} exec #{config.service_name} #{config.up_command}")
  end

  desc 'rubocop service with docker '
  task lint: :up do
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} exec -T #{config.service_name}  #{config.lint_command}")
  end

  desc 'gitpull'
  task :gitpull do
    exec_cmd('ggpull')
  end

  desc 'precheck before release'
  task precommit: %i[lint test gitpull] do |_t, _args|
    exec_cmd("TAG=#{TAG} docker-compose -f #{debug_yml} down")
    hammer.say 'Precommit succeed.'
  end

  desc 'build as docker image '
  task :build do
    exec_cmd(config.package_command.to_s)
    exec_cmd("TAG=#{TAG} docker build -t #{config.image_name}:#{TAG} -f #{config.docker_file} .")
  end

  desc 'release docker image '
  task :release do |_t, _args|
    if `TAG=#{TAG} docker images -f reference=#{config.image_name}:#{TAG} -q`.chop.empty?
      hammer.say('There is no local image for push')
    else
      remote_image = "#{docker_repo}/#{config.image_name}:#{TAG}"
      tag_cmd = "TAG=#{TAG} docker tag #{config.image_name}:#{TAG} #{remote_image}"
      exec_cmd(tag_cmd)
      push_cmd = "TAG=#{TAG} docker push #{remote_image}"
      exec_cmd(push_cmd)
      rmi_cmd = "TAG=#{TAG} docker rmi #{remote_image}"
      exec_cmd(rmi_cmd)
      hammer.say('pls commit code and push it manually！！')
    end
  end
  desc 'show docker config'
  task :info do
    last_build_time = `docker inspect -f '{{ .Created }}' #{config.image_name}`.chop
    last_build_time = Time.parse(last_build_time).localtime
    puts JSON.pretty_generate(config)
  end

  desc 'parse dockerfile and docker-compose'
  task :parse do
    match = ->(rexp) { File.open(config.docker_file).grep(rexp).first.match(rexp)[1] }
    service_config = YAML.load_file(prod_yml)
    image = service_config['services'][config.service_name]['image'].match(/((.*)\/)?(.*)/)
    image_name = image[3].gsub('${TAG}', ENV['TAG'] || 'latest')
    last_build_time = `docker inspect -f '{{ .Created }}' #{image_name}`.chop
    last_build_time = Time.parse(last_build_time).localtime
    ret = {
      base_image: match.call(/FROM (.*)/),
      author: match.call(/MAINTAINER (.*)/),
      docker_repo: image[2] || 'docker.io',
      image_name: image_name,
      last_build_at: last_build_time
    }
    File.write(config.docker_parse, ret.to_json)
    puts JSON.pretty_generate(ret)
  end

  desc 'dump docker task '
  task :dump do
    target_path = hammer.ask('target path?:')
    hammer.directory('./docker', "#{target_path}/docker")
    hammer.copy_file('./lib/tasks/docker.rake', "#{target_path}/docker/docker.rake")
    target_rakefile = "#{target_path}/Rakefile"
    File.open(target_rakefile, 'a') do |f|
      f.puts "import 'docker/docker.rake'"
      f.puts "require 'json'"
    end
  end

  private

  def exec_cmd(*cmdstr, **opt)
    hammer.say cmdstr.join(' ')
    ret = hammer.run(cmdstr.join(' '), opt)
    exit -1 unless ret
    ret
  end

  def hammer
    Hammer.new
  end
end
