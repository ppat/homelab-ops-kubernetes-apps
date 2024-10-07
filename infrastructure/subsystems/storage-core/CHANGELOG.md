# Changelog

## [0.0.2](https://github.com/ppat/homelab-ops-kubernetes-apps/compare/infra-storage-core-v0.0.1...infra-storage-core-v0.0.2) (2024-10-07)


### ✨ Features

* **infra-storage-core:** add csi-driver-nfs to enable NFS shares as PVCs ([#58](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/58)) ([6bb2daf](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/6bb2daf4c1e845c906e14dff7903f84917ac2021))
* **infra-storage-core:** add probes to collect minio bucket and resource metrics ([#85](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/85)) ([90a6dbe](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/90a6dbe1c4398130ebf6c7d01f33f7b2be52b1ff))
* **infra-storage-core:** add prometheus rule for longhorn ([#67](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/67)) ([ef16fcf](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/ef16fcfe3223fbd3902f6ba1d3e33001f56dda65))
* **infra-storage-core:** make minio config optional + add support for custom commands/service-accounts postjobs ([#77](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/77)) ([0ed32a1](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/0ed32a1f935d5b2df6bbb6c0024ed20b72e189ba))


### 🚀 Enhancements + Bug Fixes

* **infra-storage-core:** drop minio-post-job history retention + enable minio node monitoring ([#80](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/80)) ([32c1cd7](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/32c1cd77a0ef7a537f9f55255cac69b2ce3b68fa))
* **infra-storage-core:** modify minio helm release to so that PVC is created before hand ([#60](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/60)) ([c42a536](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c42a536e5049b3a038df371d1aad16127ae5b225))
* **infra-storage-core:** re-enable minio api ingress by default ([#79](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/79)) ([07d1e24](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/07d1e24178bf8cf8c0ef87a856e20277cc120765))
* **infra-storage-core:** retain minio post job history for 1 hour ([#78](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/78)) ([c7dbf60](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/c7dbf60d139756a18fb5b901854349d788f45889))
* **infra-storage-core:** tune longhorn's global settings ([#61](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/61)) ([f134d4f](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/f134d4f9374863d0172ca22132f1059f48b91b55))
* misc refactor for consistency ([#93](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/93)) ([b3ed60e](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/b3ed60eefbec76e997b0fd5d3d527217a50742ac))

## 0.0.1 (2024-09-21)


### ✨ Features

* **infra-storage-core:** add subsystem - infra-storage-core ([#10](https://github.com/ppat/homelab-ops-kubernetes-apps/issues/10)) ([7f2f642](https://github.com/ppat/homelab-ops-kubernetes-apps/commit/7f2f642e0499640849704c0c0682c9993ec88c77))
