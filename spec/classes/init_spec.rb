require 'spec_helper'
describe 'kubernetes' do
  on_supported_os.each do |os, os_facts|
    context "on #{os}" do
      let(:facts) do
        os_facts.merge({
                         ec2_metadata: {
                           hostname: 'ip-10-10-10-1.ec2.internal',
                         }
                       })
      end

      it { is_expected.to compile }

      context 'with controller => true and worker => true' do
        let(:params) do
          {
            controller: true,
           worker: true,
          }
        end

        it { is_expected.to raise_error(%r{A node can not be both a controller and a node}) }
      end

      context 'with controller => true' do
        let(:params) do
          {
            controller: true,
          }
        end

        it { is_expected.to contain_class('kubernetes') }
        it { is_expected.to contain_class('kubernetes::repos') }
        it { is_expected.to contain_class('kubernetes::packages') }
        it { is_expected.to contain_class('kubernetes::config::kubeadm') }
        it { is_expected.to contain_class('kubernetes::service') }
        it { is_expected.to contain_class('kubernetes::cluster_roles') }
        it { is_expected.to contain_class('kubernetes::kube_addons') }
      end

      context 'with worker => true and version => 1.10.2' do
        let(:params) do
          {
            worker: true,
          }
        end

        it { is_expected.to contain_class('kubernetes') }
        it { is_expected.to contain_class('kubernetes::repos') }
        it { is_expected.to contain_class('kubernetes::packages') }
        it { is_expected.not_to contain_class('kubernetes::config::kubeadm') }
        it { is_expected.not_to contain_class('kubernetes::config::worker') }
        it { is_expected.to contain_class('kubernetes::service') }
      end

      context 'with worker => true and version => 1.12.2' do
        let(:params) do
          {
            worker:  true,
          kubernetes_version: '1.12.2',
          }
        end

        it { is_expected.not_to contain_class('kubernetes::config::kubeadm') }
        it { is_expected.to contain_class('kubernetes::config::worker') }
      end

      context 'with node_label => foo and cloud_provider => undef' do
        let(:params) do
          {
            :worker => true,
          :node_label => 'foo',
          :cloud_provider => :undef,
          }
        end

        it { is_expected.not_to contain_notify('aws_node_name') }
      end

      context 'with node_label => foo and cloud_provider => aws' do
        let(:params) do
          {
            worker: true,
          node_label: 'foo',
          cloud_provider: 'aws',
          }
        end

        it { is_expected.to contain_notify('aws_name_override') }
      end

      context 'with node_label => undef and cloud_provider => aws' do
        let(:params) do
          {
            :worker => true,
          :node_label => :undef,
          :cloud_provider => 'aws',
          }
        end

        it { is_expected.not_to contain_notify('aws_name_override') }
      end

      context 'with invalid node_label should not allow code injection' do
        let(:params) do
          {
            worker: true,
          node_label: 'hostname;rm -rf /',
          }
        end

        it { is_expected.to raise_error(%r{Evaluation Error: Error while evaluating}) }
      end

      context 'with system reserved resources' do
        let(:params) do
          {
            kubernetes_version: '1.25.4',
            worker: true,
            system_reserved: {
              cpu: '1.0',
              memory: '1Gi',
              'ephemeral-storage': '10Gi',
            },
          }
        end

        let(:config_yaml) { YAML.safe_load(catalogue.resource('file', '/etc/kubernetes/config.yaml').send(:parameters)[:content]) }

        it { is_expected.to contain_file('/etc/kubernetes/config.yaml').with_content(%r{system-reserved:\n}) }

        it 'includes system reserved resources' do
          is_expected.to contain_file('/etc/kubernetes/config.yaml').with_content(
          %r{kubeletExtraArgs:\n    system-reserved:\n      cpu=1.0\n      memory=1Gi\n      ephemeral-storage=10Gi\n},
        )
        end
      end
    end
  end
end
