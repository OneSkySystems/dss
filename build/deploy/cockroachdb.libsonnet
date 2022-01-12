local base = import 'base.libsonnet';
local util = import 'util.libsonnet';
local volumes = import 'volumes.libsonnet';

{
  StatefulSet(metadata): base.StatefulSet(metadata, 'cockroachdb') {
    metadata+: {
      namespace: metadata.namespace,
    },
    spec+: {
      serviceName: 'cockroachdb',
      template+: {
        spec+: {
          serviceAccountName: 'cockroachdb',
          volumes: volumes.cockroachVolumes,
          affinity: {
            podAntiAffinity: {
              preferredDuringSchedulingIgnoredDuringExecution: [
                {
                  weight: 100,
                  podAffinityTerm: {
                    labelSelector: {
                      matchExpressions: [
                        {
                          key: 'app',
                          operator: 'In',
                          values: [
                            'cockroachdb',
                          ],
                        },
                      ],
                    },
                    topologyKey: 'kubernetes.io/hostname',
                  },
                },
              ],
            },
          },
          soloContainer:: base.Container('cockroachdb') {
            image: metadata.cockroach.image,
            volumeMounts: volumes.cockroachMounts,
            ports: [
              {
                name: 'cockroach',
                containerPort: metadata.cockroach.grpc_port,
              },
              {
                name: 'http',
                containerPort: metadata.cockroach.http_port,
              },
            ],
            env: [
              {
                name: 'COCKROACH_CHANNEL',
                value: 'kubernetes-multiregion',
              },
            ],
            livenessProbe: {
              httpGet: {
                path: '/health',
                port: 'http',
                scheme: 'HTTPS',
              },
              initialDelaySeconds: 30,
              periodSeconds: 5,
            },
            readinessProbe: {
              httpGet: {
                path: '/health?ready=1',
                port: 'http',
                scheme: 'HTTPS',
              },
              initialDelaySeconds: 10,
              periodSeconds: 5,
              failureThreshold: 2,
            },
            command: [
              '/bin/bash',
              '-ecx',
              'exec /cockroach/cockroach start ' + std.join(' ', util.makeArgs(self.command_args_)),
            ],
            command_args_:: {
              'certs-dir': '/cockroach/cockroach-certs',
              // Check for the presence of 'metadata.cockroach.hostnamePrefix' for advertise-addr
              // If we don't define it in our workspace, then fall back to the default interuss/dss behavior with no hostname prefix
              'advertise-addr': if metadata.single_cluster
                  then '$(hostname -f)'
                  else if std.objectHas(metadata.cockroach, 'hostnamePrefix')
                    then metadata.cockroach.hostnamePrefix + '${HOSTNAME##*-}.' + metadata.cockroach.hostnameSuffix else '${HOSTNAME##*-}.' + metadata.cockroach.hostnameSuffix,
              // Check for the presence of 'metadata.cockroach.initialJoinHosts'
              // If we don't define it in our workspace, then fall back to the default interuss/dss behavior of just relying on ['cockroachdb-0.cockroachdb']
              join: std.join(',', if std.objectHas(metadata.cockroach, 'initialJoinHosts') then metadata.cockroach.initialJoinHosts else ['cockroachdb-0.cockroachdb'] +
                if metadata.single_cluster then [] else metadata.cockroach.JoinExisting),
              logtostderr: true,
              locality: 'zone=' + metadata.cockroach.locality,
              'locality-advertise-addr': 'zone=' + metadata.cockroach.locality + '@$(hostname -f)',
              'http-addr': '0.0.0.0',
              cache: '25%',
              'max-sql-memory': '25%',
            },
          },
          terminationGracePeriodSeconds: 60,
        },
      },
      podManagementPolicy: 'Parallel',
      volumeClaimTemplates: [
        {
          metadata: {
            name: 'datadir',
          },
          spec: {
            storageClassName: 'gp2',
            accessModes: [
              'ReadWriteOnce',
            ],
            resources: {
              requests: {
                storage: '100Gi',
              },
            },
          },
        },
      ],
    },
  },
}
