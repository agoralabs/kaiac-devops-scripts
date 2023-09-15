#!/bin/bash

THE_DATE=$(date '+%Y-%m-%d %H:%M:%S')
echo "Build started on $THE_DATE"

source_folder=$TF_VAR_ENV_APP_BE_LOCAL_SOURCE_FOLDER

mkdir -p $source_folder/tmp
chmod 777 $source_folder/tmp

arraytpl=($(ls -d $source_folder/devops/*.template))

for template in "${arraytpl[@]}"
do
    pattern=${template%.template}
    generated=${pattern##*/}
    log_msg "generate $generated file..."
    pattern=${template%.template}
    appenvsubstr $template $source_folder/$generated
done

#move generated application.yml

cp $source_folder/application.yml $source_folder/src/main/resources/application.yml

#For spring boot only
mvnw_file=$source_folder/mvnw
if [ -f "$mvnw_file" ]
then
    chmod 777 $mvnw_file
    log_msg "Build spring boot app with $mvnw_file..."
    $mvnw_file clean install -DskipTests -f $source_folder/pom.xml
fi

authenticate_to_ecr $TF_VAR_ENV_APP_GL_AWS_ACCOUNT_ID $TF_VAR_ENV_APP_GL_AWS_REGION_ECR

log_msg "Building the Docker image..."
docker build -t $TF_VAR_ENV_APP_GL_NAME:$TF_VAR_ENV_APP_BE_NAMESPACE'_'$TF_VAR_ENV_APP_GL_STAGE $source_folder

log_msg "Run services for the $TF_VAR_ENV_APP_GL_NAME environment..."
docker compose -f $source_folder/docker-compose.yml up -d