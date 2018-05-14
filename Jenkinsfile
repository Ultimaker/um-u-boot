pipeline {
  agent {
    node {
      label 'embedded-docker'
    }
    
  }
  stages {
    stage('Build') {
      steps {
        sh './docker_build.sh'
      }
    }
  }
}
