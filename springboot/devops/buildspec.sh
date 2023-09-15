#!/bin/bash

THE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Build started on $THE_DATE"

appenvsubstr(){
    p_template=$1
    p_destination=$2
    envsubst '$TF_VAR_ENV_APP_GL_NAME' < $p_template \
    | envsubst '$TF_VAR_ENV_APP_GL_STAGE' \
    | envsubst '$TF_VAR_ENV_APP_BE_NAMESPACE' \
    | envsubst '$TF_VAR_ENV_APP_BE_LOCAL_SOURCE_FOLDER' \
    | envsubst '$TF_VAR_ENV_APP_BE_LOCAL_PORT' \
    | envsubst '$TF_VAR_ENV_APP_BE_URL' \
    | envsubst '$TF_VAR_ENV_APP_DB_HOST' \
    | envsubst '$TF_VAR_ENV_APP_DB_NAME' \
    | envsubst '$TF_VAR_ENV_APP_DB_USERNAME' \
    | envsubst '$TF_VAR_ENV_APP_DB_PASSWORD' \
    | envsubst '$TF_VAR_ENV_APP_DB_PORT' \
    | envsubst '$TF_VAR_ENV_APP_GL_NAMESPACE' \
    | envsubst '$TF_VAR_ENV_APP_GL_AWS_ACCOUNT_ID' \
    | envsubst '$TF_VAR_ENV_APP_GL_AWS_REGION' \
    | envsubst '$TF_VAR_ENV_APP_GL_SCRIPT_MODE' \
    | envsubst '$TF_VAR_ENV_APP_BE_EKS_CLUSTER_NAME' \
    | envsubst '$TF_VAR_ENV_APP_BE_DOMAIN_NAME' \
    | envsubst '$TF_VAR_ENV_APP_BE_SSL_CERT_ARN' \
    | envsubst '$TF_VAR_ENV_APP_GL_REPO_JDK_NAME' \
    | envsubst '$TF_VAR_ENV_APP_GL_REPO_JDK_TAG' \
    | envsubst '$TF_VAR_ENV_APP_GL_AWS_REGION_ECR' > $p_destination
}

appenvsubstr devops/appspec.yml.template appspec.yml
appenvsubstr devops/appspec.sh.template devops/appspec.sh
appenvsubstr devops/application.yml.template src/main/resources/application.yml
chmod 777 devops/appspec.sh

chmod +x ./mvnw
./mvnw clean install -DskipTests

if [ "$TF_VAR_ENV_APP_GL_SCRIPT_MODE" == "CLOUDOCKER" ] 
then

    appenvsubstr devops/Dockerfile.template Dockerfile
    appenvsubstr devops/docker-compose.yml.template docker-compose.yml

elif [ "$TF_VAR_ENV_APP_GL_SCRIPT_MODE" == "CLOUDEKS" ] 
then
    echo "Generating Dockerfile..."
    appenvsubstr devops/Dockerfile.template Dockerfile

    echo "Generating app-kubernetes.yaml..."
    appenvsubstr devops/app-kubernetes.yaml.template app-kubernetes.yaml

    echo "Generating app-service.yaml..."
    appenvsubstr devops/app-service.yaml.template app-service.yaml

    echo "Login into ecr..."
    aws ecr get-login-password --region $TF_VAR_ENV_APP_GL_AWS_REGION_ECR | docker login --username AWS --password-stdin $TF_VAR_ENV_APP_GL_AWS_ACCOUNT_ID.dkr.ecr.$TF_VAR_ENV_APP_GL_AWS_REGION_ECR.amazonaws.com

    echo "Building the Docker image..."
    docker build -t $TF_VAR_ENV_APP_GL_NAME:${TF_VAR_ENV_APP_BE_NAMESPACE}_${TF_VAR_ENV_APP_GL_NAME} .

    echo "Create $TF_VAR_ENV_APP_GL_NAME repository..."
    aws ecr describe-repositories --repository-names $TF_VAR_ENV_APP_GL_NAME || aws ecr create-repository --repository-name $TF_VAR_ENV_APP_GL_NAME

    echo "Tag your image with the Amazon ECR registry..."
    docker tag $TF_VAR_ENV_APP_GL_NAME:${TF_VAR_ENV_APP_BE_NAMESPACE}_${TF_VAR_ENV_APP_GL_NAME} $TF_VAR_ENV_APP_GL_AWS_ACCOUNT_ID.dkr.ecr.$TF_VAR_ENV_APP_GL_AWS_REGION_ECR.amazonaws.com/$TF_VAR_ENV_APP_GL_NAME:$TF_VAR_ENV_APP_BE_NAMESPACE'_'$TF_VAR_ENV_APP_GL_NAME

    echo "Push the image to ecr..."
    docker push $TF_VAR_ENV_APP_GL_AWS_ACCOUNT_ID.dkr.ecr.$TF_VAR_ENV_APP_GL_AWS_REGION_ECR.amazonaws.com/$TF_VAR_ENV_APP_GL_NAME:$TF_VAR_ENV_APP_BE_NAMESPACE'_'$TF_VAR_ENV_APP_GL_NAME

    echo "Updating kubeconfig..."
    aws eks update-kubeconfig --region $TF_VAR_ENV_APP_GL_AWS_REGION --name $TF_VAR_ENV_APP_BE_EKS_CLUSTER_NAME
    
    cat app-kubernetes.yaml
    cat app-service.yaml

    echo "Trying kubectl apply -f app-kubernetes.yaml..."
    kubectl apply -f app-kubernetes.yaml -n ${TF_VAR_ENV_APP_BE_KUBERNETES_NAMESPACE}
    
    echo "Trying kubectl apply -f app-service.yaml..."
    kubectl apply -f app-service.yaml -n ${TF_VAR_ENV_APP_BE_KUBERNETES_NAMESPACE}

fi



