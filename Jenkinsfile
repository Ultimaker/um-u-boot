pipeline {
  agent {
    node {
      label 'slave-debian-stretch-def079b0'
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