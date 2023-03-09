
KIND_INSTANCE=seldon

# creates a K8s instance
.PHONY: k8s_new
k8s_new:
	kind create cluster --config ./kind/kind.yaml --name $(KIND_INSTANCE)

# deletes a k8s instance
.PHONY: k8s_drop
k8s_drop:
	kind delete cluster --name $(KIND_INSTANCE)

# sets KUBECONFIG for the K8s instance
.PHONY: k8s_connect
k8s_connect:
	kind export kubeconfig --name $(KIND_INSTANCE)

.PHONY: install_kafka
install_kafka: k8s_connect
	helm upgrade --install strimzi-kafka-operator \
  	strimzi/strimzi-kafka-operator \
  	--namespace seldon-mesh --create-namespace \
  	--set featureGates='+UseKRaft\,+UseStrimziPodSets'

.PHONY: install_minio
install_minio: k8s_connect
	# install minio as we'd like an S3 like backend
	# configure with 1 replicas and a small amount of memory
	helm install --namespace minio --create-namespace \
		--values ./k8s/minio/values.yaml \
		minio minio/minio

.PHONY: install_seldon
install_seldon: k8s_connect
	kubectl apply -f ./k8s/namespace.yaml
	kubectl apply -f ./k8s/kafka/broker.yaml -n seldon-mesh
	kubectl apply -f ./k8s/kafka/ui.yaml -n seldon-mesh
	kubectl apply -f ./k8s/minio/secret.yaml -n seldon-mesh
	helm install seldon-core-v2-crds seldon-charts/seldon-core-v2-crds
	helm install seldon-core-v2 seldon-charts/seldon-core-v2-setup --namespace seldon-mesh --create-namespace
	helm install seldon-servers-v2 seldon-charts/seldon-core-v2-servers --namespace seldon-mesh
	
.PHONY: helm_init
helm_init:
	helm repo add strimzi https://strimzi.io/charts/
	helm repo add seldon-charts https://seldonio.github.io/helm-charts
	helm repo add minio https://charts.min.io/
	helm repo update strimzi
	helm repo update seldon-charts
	helm repo update minio

.PHONY: boot
boot: k8s_new helm_init install_kafka install_seldon
