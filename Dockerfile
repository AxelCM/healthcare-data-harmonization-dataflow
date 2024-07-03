FROM ubuntu:20.04

# Configurar el entorno no interactivo
ENV DEBIAN_FRONTEND=noninteractive

# Actualizar los repositorios e instalar las dependencias necesarias
RUN apt-get update && apt-get install -y \
    build-essential \
    gcc \
    curl \
    git \
    openjdk-11-jdk \
    unzip \
    gnupg \
    lsb-release

# Validar la instalación de Java
RUN java -version

# Instalar Go
RUN curl -OL https://golang.org/dl/go1.14.15.linux-amd64.tar.gz \
    && tar -C /usr/local -xzf go1.14.15.linux-amd64.tar.gz \
    && rm go1.14.15.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin

# Setup JAVA_HOME -- useful for docker commandline
ENV JAVA_HOME /usr/lib/jvm/java-11-openjdk-arm64
ENV PATH $PATH:$JAVA_HOME/bin

# Instalar Gradle
RUN curl -L https://services.gradle.org/distributions/gradle-7.6-bin.zip -o gradle-7.6-bin.zip \
    && unzip gradle-7.6-bin.zip \
    && mv gradle-7.6 /opt/gradle \
    && ln -s /opt/gradle/bin/gradle /usr/bin/gradle \
    && rm gradle-7.6-bin.zip

# Instalar Protoc
RUN curl -OL https://github.com/protocolbuffers/protobuf/releases/download/v3.14.0/protoc-3.14.0-linux-x86_64.zip \
    && unzip protoc-3.14.0-linux-x86_64.zip -d /usr/local \
    && rm protoc-3.14.0-linux-x86_64.zip

# Instalar Google Cloud SDK
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
    && curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - \
    && apt-get update && apt-get install -y google-cloud-sdk

# Copiar las credenciales de la cuenta de servicio al contenedor
COPY ./credentials.json /root/.gcloud/credentials.json

# Configurar las variables de entorno para la autenticación
ENV GOOGLE_APPLICATION_CREDENTIALS="/root/.gcloud/credentials.json"

# Agregar clave pública a GitHub
COPY ./id_rsa.pub /root/.ssh/id_rsa.pub

# Clonar y configurar el proyecto
RUN git clone https://github.com/AxelCM/healthcare-data-harmonization-dataflow.git /opt/healthcare-data-harmonization-dataflow
WORKDIR /opt/healthcare-data-harmonization-dataflow

# Ejecutar el wrapper de Gradle y construir el JAR
RUN gradle wrapper --gradle-version 7.6
RUN ./build_deps.sh && ./gradlew shadowJar

# Definir variables de entorno necesarias
ENV PROJECT="qa-app-c4bd3"
ENV SUBSCRIPTION="hl7subscription"
ENV ERROR_BUCKET="qa-app-c4bd3-df-pipeline"
ENV MAPPING_BUCKET="qa-app-c4bd3-df-pipeline"
ENV LOCATION="us-east1"
ENV DATASET="datastore"
ENV FHIRSTORE="fhirstore"
ENV REGION="us-east1"

# Comando para ejecutar el pipeline
CMD java -jar build/libs/converter-0.1.0-all.jar --pubSubSubscription="projects/${PROJECT?}/subscriptions/${SUBSCRIPTION?}" \
                                             --readErrorPath="gs://${ERROR_BUCKET?}/read/" \
                                             --writeErrorPath="gs://${ERROR_BUCKET?}/write/" \
                                             --mappingErrorPath="gs://${ERROR_BUCKET?}/error/mapping/mapping_error.txt" \
                                             --mappingPath="gs://${MAPPING_BUCKET?}/mapping/mapping_configs/hl7v2_fhir_r4/configurations/main.textproto" \
                                             --importRoot="gs://${MAPPING_BUCKET?}/mapping/mapping_configs/hl7v2_fhir_r4" \
                                             --fhirStore="projects/${PROJECT?}/locations/${LOCATION?}/datasets/${DATASET?}/fhirStores/${FHIRSTORE?}" \
                                             --runner=DataflowRunner \
                                             --region=${REGION?} \
                                             --project=${PROJECT?} \
                                             --serviceAccount=healthcare-qa@qa-app-c4bd3.iam.gserviceaccount.com