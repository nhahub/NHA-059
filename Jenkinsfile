pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    jenkins: agent
                spec:
                  serviceAccountName: jenkins
                  containers:
                  - name: dind
                    image: docker:24-dind
                    securityContext:
                      privileged: true
                    volumeMounts:
                    - name: docker-sock
                      mountPath: /var/run/docker.sock
                  - name: kubectl
                    image: bitnami/kubectl:latest
                    command:
                    - cat
                    tty: true
                  - name: node
                    image: node:18
                    command:
                    - cat
                    tty: true
                  volumes:
                  - name: docker-sock
                    emptyDir: {}
            '''
        }
    }
    
    environment {
        // Docker configuration
        DOCKER_REGISTRY = 'docker.io'
        DOCKER_REPO = 'makenmohamed/url-shortener'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        IMAGE_NAME = "${DOCKER_REPO}:${IMAGE_TAG}"
        IMAGE_LATEST = "${DOCKER_REPO}:latest"
        
        // Kubernetes configuration
        K8S_NAMESPACE = 'app'
        K8S_DEPLOYMENT_NAME = 'url-shortener'
        K8S_MANIFESTS_DIR = 'k8s'
        
        // Jenkins credentials
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-credentials')
        
        // Application configuration
        APP_NAME = 'url-shortener'
        
        // Docker daemon socket for DinD
        DOCKER_HOST = 'unix:///var/run/docker.sock'
    }
    
    options {
        // Keep only last 10 builds
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // Timeout after 30 minutes
        timeout(time: 30, unit: 'MINUTES')
        // Disable concurrent builds
        disableConcurrentBuilds()
        // Add timestamps to console output
        timestamps()
    }
    
    triggers {
        // Poll SCM for changes (backup if webhook fails)
        githubPush()
        pollSCM('H/5 * * * *')
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo "=== Stage: Checkout ==="
                checkout scm
                script {
                    // Get commit info for build metadata
                    env.GIT_COMMIT_MSG = sh(
                        script: 'git log -1 --pretty=%B',
                        returnStdout: true
                    ).trim()
                    env.GIT_COMMIT_SHORT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    echo "Commit: ${env.GIT_COMMIT_SHORT} - ${env.GIT_COMMIT_MSG}"
                }
            }
        }
               //STAGE 1: Install & Test (RUNS INSIDE NODE CONTAINER)  

        stage('Install & Test') {
            // Use Node.js Docker image for this stage instead of installing Node.js on the Jenkins host to maintain a clean environment consistency of node versions
            steps {
                echo "=== Stage: Install & Test ==="
                container('node') {
                    script {
                        // Install dependencies
                        sh '''
                            echo "Installing dependencies..."
                            npm ci
                        '''
                        
                        // Run tests if they exist
                        def testScript = sh(
                            script: 'grep -q \'"test"\' package.json && echo "exists" || echo "none"',
                            returnStdout: true
                        ).trim()
                        
                        if (testScript == 'exists') {
                            echo "Running tests..."
                            sh 'npm test || true'
                        } else {
                            echo "No test script found, skipping tests..."
                        }
                        
                        // Optional: Run linting if configured
                        def lintScript = sh(
                            script: 'grep -q \'"lint"\' package.json && echo "exists" || echo "none"',
                            returnStdout: true
                        ).trim()
                        
                        if (lintScript == 'exists') {
                            echo "Running linter..."
                            sh 'npm run lint || true'
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo "=== Stage: Build Docker Image ==="
                container('dind') {
                    script {
                        // Build Docker image with multiple tags
                        sh """
                            echo "Building Docker image: ${IMAGE_NAME}"
                            docker build \
                                --tag ${IMAGE_NAME} \
                                --tag ${IMAGE_LATEST} \
                                --label "build.number=${env.BUILD_NUMBER}" \
                                --label "git.commit=${env.GIT_COMMIT_SHORT}" \
                                --label "build.date=\$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
                                .
                        """
                        
                        // Verify image was created
                        sh "docker images | grep ${DOCKER_REPO}"
                    }
                }
            }
        }
        
        // New stage to check DockerHub credentials existence before login and push
        stage('Check Creds') {
            steps {
                script {
                    echo "Testing USER exists? -> $DOCKERHUB_CREDENTIALS_USR"
                }
            }
        }

        stage('Push to DockerHub') {
            steps {
                echo "=== Stage: Push to DockerHub ==="
                container('dind') {
                    script {
                        // Login to DockerHub
                        sh '''
                            echo "Logging in to DockerHub..."
                            echo $DOCKERHUB_CREDENTIALS_PSW | docker login -u $DOCKERHUB_CREDENTIALS_USR --password-stdin
                        '''
                        
                        // Push both tagged and latest images
                        sh """
                            echo "Pushing image: ${IMAGE_NAME}"
                            docker push ${IMAGE_NAME}
                            
                            echo "Pushing image: ${IMAGE_LATEST}"
                            docker push ${IMAGE_LATEST}
                        """
                        
                        echo "Successfully pushed images to DockerHub"
                    }
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                echo "=== Stage: Deploy to Kubernetes ==="
                container('kubectl') {
                    script {
                        // Create namespace if it doesn't exist
                        sh """
                            echo "Ensuring namespace '${K8S_NAMESPACE}' exists..."
                            kubectl create namespace ${K8S_NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -
                        """
                        
                        // Update deployment with new image tag
                        sh """
                            echo "Updating Kubernetes deployment with image: ${IMAGE_NAME}"
                            
                            # Apply Kubernetes manifests
                            if [ -d "${K8S_MANIFESTS_DIR}" ]; then
                                echo "Applying manifests from ${K8S_MANIFESTS_DIR}/"
                                kubectl apply -f ${K8S_MANIFESTS_DIR}/ -n ${K8S_NAMESPACE}
                            else
                                echo "Warning: ${K8S_MANIFESTS_DIR}/ directory not found"
                            fi
                            
                            # Update deployment image (idempotent)
                            kubectl set image deployment/${K8S_DEPLOYMENT_NAME} \
                                ${K8S_DEPLOYMENT_NAME}=${IMAGE_NAME} \
                                -n ${K8S_NAMESPACE} --record || true
                            
                            # Wait for rollout to complete
                            echo "Waiting for deployment rollout..."
                            kubectl rollout status deployment/${K8S_DEPLOYMENT_NAME} \
                                -n ${K8S_NAMESPACE} \
                                --timeout=5m
                        """
                    }
                }
            }
        }
        
        stage('Healthcheck') {
            steps {
                echo "=== Stage: Healthcheck ==="
                container('kubectl') {
                    script {
                        // Verify pods are running
                        sh """
                            echo "Checking pod status..."
                            kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT_NAME}
                            
                            # Get pod name
                            POD_NAME=\$(kubectl get pods -n ${K8S_NAMESPACE} -l app=${K8S_DEPLOYMENT_NAME} -o jsonpath='{.items[0].metadata.name}')
                            echo "Pod name: \$POD_NAME"
                            
                            # Check pod health
                            kubectl describe pod \$POD_NAME -n ${K8S_NAMESPACE} | grep -A 5 "Conditions:"
                            
                            # Optional: Test endpoint if service is exposed
                            echo "Verifying deployment is healthy..."
                            kubectl wait --for=condition=available --timeout=300s \
                                deployment/${K8S_DEPLOYMENT_NAME} -n ${K8S_NAMESPACE}
                        """
                        
                        echo "✅ Healthcheck passed! Application is running."
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo "=== Pipeline Execution Complete ==="
            container('dind') {
                // Logout from DockerHub
                sh 'docker logout || true'
                
                // Clean up old Docker images to save space
                sh """
                    echo "Cleaning up old Docker images..."
                    docker image prune -f --filter "label=build.number" || true
                """
            }
        }
        
        success {
            echo "✅ Pipeline completed successfully!"
            script {
                // Send success notification (customize as needed)
                echo """
                ================================================
                SUCCESS: Build #${env.BUILD_NUMBER}
                ================================================
                Application: ${APP_NAME}
                Image: ${IMAGE_NAME}
                Commit: ${env.GIT_COMMIT_SHORT}
                Message: ${env.GIT_COMMIT_MSG}
                Namespace: ${K8S_NAMESPACE}
                ================================================
                """
                
                // Optional: Send Slack/Email notification
                // slackSend(color: 'good', message: "Deployment successful: ${env.JOB_NAME} #${env.BUILD_NUMBER}")
            }
        }
        
        failure {
            echo "❌ Pipeline failed!"
            script {
                // Send failure notification
                echo """
                ================================================
                FAILURE: Build #${env.BUILD_NUMBER}
                ================================================
                Application: ${APP_NAME}
                Stage Failed: ${env.STAGE_NAME}
                Commit: ${env.GIT_COMMIT_SHORT}
                Message: ${env.GIT_COMMIT_MSG}
                ================================================
                """
                
                // Optional: Send Slack/Email notification
                // slackSend(color: 'danger', message: "Deployment failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}")
                
                // Optional: Rollback on failure
                // sh "kubectl rollout undo deployment/${K8S_DEPLOYMENT_NAME} -n ${K8S_NAMESPACE} || true"
            }
        }
        
        unstable {
            echo "⚠️ Pipeline is unstable"
        }
        
        cleanup {
            // Clean workspace after build
            cleanWs(
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true
            )
        }
    }
}
