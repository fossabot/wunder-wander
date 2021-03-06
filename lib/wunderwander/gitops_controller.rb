# frozen_string_literal: true

# check for GitOp CRDs and deploy a worker
$LOAD_PATH << '.'
require 'k8s-client'
require 'lib/k8s_helpers'
require 'lib/log_helpers'
require 'lib/wunderwander_helpers'
require 'mustache'

module WunderWander
  # Worker template
  class GitopsWorker < Mustache
    self.template_file = 'controller/worker-template.yaml.mustache'
  end

  # Controller
  class GitopsController
    def initialize
      @logger = LogHelpers.create_logger
      @k8s_client = K8sHelpers::Client.new @logger

      @logger.info '---'
      @logger.info "WunderWander GitOps Controller v#{WunderWanderHelpers::VERSION}"
      @logger.info '---'

      # create secret
      @k8s_client.create_key_pair
    end

    def render_worker_template(resource)
      template = GitopsWorker.new
      template[:name] = "worker-#{resource.metadata.name}"
      template[:image] = WunderWanderHelpers::IMAGE
      template[:git_branch] = resource.spec.branch
      template[:git_repo] = resource.spec.repo
      template[:git_name] = resource.metadata.name
      template[:gitops_namespace] = "#{resource.metadata.name}-#{resource.spec.branch}"
      template[:namespace] = K8sHelpers::GITOPS_NAMESPACE
      K8s::Resource.new(YAML.safe_load(template.render))
    end

    def deploy_worker(worker)
      @k8s_client.client.get_resource(worker)
    rescue K8s::Error::NotFound
      @k8s_client.client.create_resource(worker)
      @logger.info "Worker for #{resource.metadata.name} deployed"
    end

    def observe_and_act
      api = @k8s_client.client.api('io.wunderwander/v1')
      gitops = api.resource('gitops', namespace: K8sHelpers::GITOPS_NAMESPACE)
      gitops.list.each do |resource|
        worker = render_worker_template(resource)
        deploy_worker(worker)
      end
    rescue K8s::Error::NotFound
      @logger.info 'CRD not found'
    end

    def start_controller
      loop do
        observe_and_act
        @logger.info "Next check in #{WunderWanderHelpers::DEFAULT_PULL_FREQENCY} seconds"
        @logger.info '---'
        sleep(WunderWanderHelpers::DEFAULT_PULL_FREQENCY)
      end
    end
  end
end
