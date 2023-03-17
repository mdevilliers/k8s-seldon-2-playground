
KIND_INSTANCE=seldon

SELDON_NS=seldon-mesh
SELDON_OBS_NS=seldon-observability

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
  	--namespace $(SELDON_NS) --create-namespace \
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
	kubectl apply -f ./k8s/kafka/broker.yaml -n $(SELDON_NS)
	kubectl apply -f ./k8s/kafka/ui.yaml -n $(SELDON_NS)
	kubectl apply -f ./k8s/minio/secret.yaml -n $(SELDON_NS)
	helm install seldon-core-v2-crds seldon-charts/seldon-core-v2-crds
	helm install seldon-core-v2 seldon-charts/seldon-core-v2-setup --namespace $(SELDON_NS)
	helm install seldon-core-v2-servers seldon-charts/seldon-core-v2-servers --namespace $(SELDON_NS)
	kubectl apply -f ./k8s/observability/jaeger.yaml -n $(SELDON_OBS_NS)
	kubectl apply -f ./k8s/observability/prometheus.yaml -n $(SELDON_NS)
	kubectl apply -f ./k8s/observability/open-telemetry.yaml -n $(SELDON_NS)

.PHONY: install_observability
install_observability:
	helm install cert-manager jetstack/cert-manager \
  	--namespace cert-manager \
  	--create-namespace \
		--set installCRDs=true
	helm install prometheus-stack bitnami/kube-prometheus \
		-f ./k8s/observability/prometheus-operator-values.yaml \
		--namespace $(SELDON_OBS_NS) --create-namespace
	helm install jaeger-operator jaegertracing/jaeger-operator --namespace $(SELDON_OBS_NS) --create-namespace
	helm install opentelemetry-operator open-telemetry/opentelemetry-operator --namespace $(SELDON_OBS_NS) --create-namespace
	
.PHONY: helm_init
helm_init:
	helm repo add strimzi https://strimzi.io/charts/
	helm repo add seldon-charts https://seldonio.github.io/helm-charts
	helm repo add minio https://charts.min.io/
	helm repo add bitnami https://charts.bitnami.com/bitnami
	helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
	helm repo add jetstack https://charts.jetstack.io
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update

.PHONY: boot
boot: k8s_new helm_init install_kafka install_minio install_observability install_seldon
