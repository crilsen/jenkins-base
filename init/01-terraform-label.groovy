import jenkins.model.Jenkins

// Pipelines in this project target `agent { label 'terraform' }`. The
// controller is the only node in a local demo, so label it accordingly.
// For anything beyond a demo, attach a real agent instead of building on the
// controller.
def jenkins = Jenkins.get()
jenkins.setLabelString("terraform")
jenkins.setNumExecutors(2)
jenkins.save()
