
pipeline {

    parameters {
      
        booleanParam(name: 'autoApprove', defaultValue: false, description: 'Automatically run apply after generating plan?')

    }


     environment {
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION = "ap-south-1"
    }
  
   agent  any

    stages {
        stage('checkout') {
            steps {
                 script{
    
                        
                           git branch: 'main', url: 'https://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@github.com/jyoti/trfm.git'
                        
                    }
                }
            }

        stage('Plan') {
            steps {
                sh 'terraform init -input=false'
                 sh "terraform plan -input=false -out tfplan "
                sh 'terraform show -no-color tfplan > tfplan.txt'
            }
        }
        stage('Approval') {
           when {
               not {
                   equals expected: true, actual: params.autoApprove
               }
           }

           steps {
               script {
                    def plan = readFile 'tfplan.txt'
                    input message: "Do you want to apply the plan?",
                    parameters: [text(name: 'Plan', description: 'Please review the plan', defaultValue: plan)]
               }
           }
       }

        stage('Apply') {
            steps {
                echo "You have chosen terraform ${action}"
                sh "terraform ${action} -input=false tfplan"
            }
        }
    }

  }