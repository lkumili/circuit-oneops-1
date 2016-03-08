include_pack 'genericlb'

name 'docker'
description 'Docker'
type 'Platform'
category 'Infrastructure Service'

variable 'docker-root',
         :description => 'Root of the Docker runtime.',
         :value => '/var/lib/docker'

variable 'data-volume',
         :description => 'Data volume for persistent or shared data.',
         :value => '/data'

variable 'docker-repo',
         :description => 'Docker release package repository.',
         :value => ''

resource 'compute',
         :cookbook => 'oneops.1.compute',
         :design => true,
         :attributes => {:size => 'M'}

resource 'secgroup',
         :cookbook => 'oneops.1.secgroup',
         :design => true,
         :attributes => {
             :inbound => '["22 22 tcp 0.0.0.0/0", "80 80 tcp 0.0.0.0/0"]'
         },
         :requires => {
             :constraint => '1..1',
             :services => 'compute'
         }

resource 'docker_engine',
         :cookbook => 'oneops.1.docker_engine',
         :design => true,
         :requires => {:constraint => '1..1',
                       :services => 'compute,mirror'},
         :attributes => {
             :version => '1.9.1',
             :root => '$OO_LOCAL{docker-root}',
             :repo => '$OO_LOCAL{docker-repo}'
         },
         :monitors => {
             :dockerProcess => {:description => 'DockerEngine',
                                :source => '',
                                :chart => {:min => '0', :max => '100', :unit => 'Percent'},
                                :cmd => 'check_process!docker!true!docker!false',
                                :cmd_line => '/opt/nagios/libexec/check_process.sh "$ARG1$" "$ARG2$" "$ARG3$" "$ARG4$"',
                                :metrics => {
                                    :up => metric(:unit => '%', :description => 'Percent Up'),
                                },
                                :thresholds => {
                                    :dockerEngineDown => threshold('1m', 'avg', 'up', trigger('<=', 98, 1, 1), reset('>', 95, 1, 1), 'unhealthy')
                                }
             }
         }

resource 'artifact',
         :cookbook => 'oneops.1.artifact',
         :design => true,
         :requires => {:constraint => '0..*'},
         :attributes => {}

resource 'java',
         :cookbook => 'oneops.1.java',
         :design => true,
         :requires => {
             :constraint => '0..1',
             :services => 'mirror',
             :help => 'Java Programming Language Environment'
         },
         :attributes => {}

resource 'vol-docker',
         :cookbook => 'oneops.1.volume',
         :design => true,
         :requires => {:constraint => '1..1', :services => 'compute'},
         :attributes => {:mount_point => '$OO_LOCAL{docker-root}',
                         :size => '10G',
                         :device => '',
                         :fstype => 'xfs',
                         :options => ''
         },
         :monitors => {
             :usage => {:description => 'Usage',
                        :chart => {:min => 0, :unit => 'Percent used'},
                        :cmd => 'check_disk_use!:::node.workorder.rfcCi.ciAttributes.mount_point:::',
                        :cmd_line => '/opt/nagios/libexec/check_disk_use.sh $ARG1$',
                        :metrics => {:space_used => metric(:unit => '%', :description => 'Disk Space Percent Used'),
                                     :inode_used => metric(:unit => '%', :description => 'Disk Inode Percent Used')},
                        :thresholds => {
                            :LowDiskSpaceCritical => threshold('1m', 'avg', 'space_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1)),
                            :LowDiskInodeCritical => threshold('1m', 'avg', 'inode_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1))
                        }
             }
         }

resource 'vol-data',
         :cookbook => 'oneops.1.volume',
         :design => true,
         :requires => {:constraint => '1..1', :services => 'compute'},
         :attributes => {:mount_point => '$OO_LOCAL{data-volume}',
                         :size => '100%FREE',
                         :device => '',
                         :fstype => 'xfs',
                         :options => ''
         },
         :monitors => {
             :usage => {:description => 'Usage',
                        :chart => {:min => 0, :unit => 'Percent used'},
                        :cmd => 'check_disk_use!:::node.workorder.rfcCi.ciAttributes.mount_point:::',
                        :cmd_line => '/opt/nagios/libexec/check_disk_use.sh $ARG1$',
                        :metrics => {:space_used => metric(:unit => '%', :description => 'Disk Space Percent Used'),
                                     :inode_used => metric(:unit => '%', :description => 'Disk Inode Percent Used')},
                        :thresholds => {
                            :LowDiskSpaceCritical => threshold('1m', 'avg', 'space_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1)),
                            :LowDiskInodeCritical => threshold('1m', 'avg', 'inode_used', trigger('>=', 90, 5, 2), reset('<', 85, 5, 1))
                        }
             }
         }

[{:from => 'vol-docker', :to => 'os'},
 {:from => 'java', :to => 'os'},
 {:from => 'vol-data', :to => 'vol-docker'},
 {:from => 'vol-data', :to => 'storage'},
 {:from => 'docker_engine', :to => 'vol-data'},
 {:from => 'file', :to => 'vol-data'},
 {:from => 'share', :to => 'vol-data'},
 {:from => 'artifact', :to => 'docker_engine'}
].each { |link|
  relation "#{link[:from]}::depends_on::#{link[:to]}",
           :relation_name => 'DependsOn',
           :from_resource => link[:from],
           :to_resource => link[:to],
           :attributes => {:flex => false, :min => 1, :max => 1}
}

# Hostname depends_on
['hostname'].each { |from|
  relation "#{from}::depends_on::compute",
           :relation_name => 'DependsOn',
           :from_resource => from,
           :to_resource => 'compute',
           :attributes => {:propagate_to => 'from', :flex => false, :min => 1, :max => 1}
}

# FQDN flexing
['fqdn'].each { |from|
  relation "#{from}::depends_on::compute",
           :only => %w(_default single),
           :relation_name => 'DependsOn',
           :from_resource => from,
           :to_resource => 'compute',
           :attributes => {:propagate_to => 'from', :flex => false, :min => 1, :max => 1}
}


# Managed_via
%w(vol-docker vol-data docker_engine artifact java daemon).each { |from|
  relation "#{from}::managed_via::compute",
           :except => ['_default'],
           :relation_name => 'ManagedVia',
           :from_resource => from,
           :to_resource => 'compute',
           :attributes => {}
}