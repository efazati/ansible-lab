# Example Kubernetes Deployments

This directory contains example applications to test your Kubernetes cluster.

## NGINX Demo Application

Deploy a simple NGINX application with 3 replicas:

```bash
# Deploy
kubectl apply -f nginx-deployment.yaml

# Check status
kubectl get all -n demo

# Get NodePort
kubectl get svc -n demo nginx

# Access the application
# Get a node IP
kubectl get nodes -o wide

# Access via NodePort (example)
curl http://<node-ip>:<nodeport>
```

## Expected Output

```bash
$ kubectl get all -n demo

NAME                         READY   STATUS    RESTARTS   AGE
pod/nginx-5d7b8c9d8f-abcd1   1/1     Running   0          1m
pod/nginx-5d7b8c9d8f-efgh2   1/1     Running   0          1m
pod/nginx-5d7b8c9d8f-ijkl3   1/1     Running   0          1m

NAME            TYPE       CLUSTER-IP      EXTERNAL-IP   PORT(S)        AGE
service/nginx   NodePort   10.233.10.123   <none>        80:31234/TCP   1m

NAME                    READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx   3/3     3            3           1m

NAME                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-5d7b8c9d8f   3         3         3       1m
```

## Test the Application

```bash
# Get worker node IP
source ../.env
WORKER_IP=$(echo $HOSTNAME_K8S_WORKER_1 | cut -d'.' -f1-4)

# Get NodePort
NODEPORT=$(kubectl get svc -n demo nginx -o jsonpath='{.spec.ports[0].nodePort}')

# Access the application
curl http://$HOSTNAME_K8S_WORKER_1:$NODEPORT
```

## Cleanup

```bash
kubectl delete -f nginx-deployment.yaml
```

## More Examples

### Deploy from CLI

```bash
# Create deployment
kubectl create deployment hello --image=nginx:alpine -n demo

# Expose it
kubectl expose deployment hello --port=80 --type=NodePort -n demo

# Scale it
kubectl scale deployment hello --replicas=5 -n demo

# Check status
kubectl get all -n demo
```

### Port Forward (for testing)

```bash
# Forward local port to pod
kubectl port-forward -n demo deployment/nginx 8080:80

# Access from your local machine
curl http://localhost:8080
```

### View Logs

```bash
# Get pod name
POD=$(kubectl get pods -n demo -l app=nginx -o jsonpath='{.items[0].metadata.name}')

# View logs
kubectl logs -n demo $POD

# Follow logs
kubectl logs -n demo $POD -f
```

### Execute Commands in Pod

```bash
# Get shell in pod
kubectl exec -it -n demo $POD -- /bin/sh

# Run command
kubectl exec -n demo $POD -- ls -la /usr/share/nginx/html
```

## Advanced Examples

### ConfigMap Example

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: demo
data:
  index.html: |
    <html>
    <body>
      <h1>Hello from Kubernetes!</h1>
      <p>This is served from a ConfigMap</p>
    </body>
    </html>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-configmap
  namespace: demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nginx-configmap
  template:
    metadata:
      labels:
        app: nginx-configmap
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: nginx-config
```

Save this to `nginx-configmap.yaml` and deploy:

```bash
kubectl apply -f nginx-configmap.yaml
kubectl port-forward -n demo deployment/nginx-configmap 8080:80
curl http://localhost:8080
```

