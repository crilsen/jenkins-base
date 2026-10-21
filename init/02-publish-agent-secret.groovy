import hudson.slaves.SlaveComputer
import jenkins.model.Jenkins

// The inbound agent needs the JNLP secret Jenkins generates for its node. The node
// is declared in CasC (casc/jenkins.yaml -> jenkins.nodes), and CasC is applied at
// the end of boot, after init scripts run — so this polls in a background thread and
// publishes the secret to the shared directory the agent container reads.
//
// The secret is written with 0600 permissions and never logged.

def nodeName = System.getenv('AGENT_NODE_NAME') ?: 'agent-1'
def outDir = new File(System.getenv('AGENT_SECRET_DIR') ?: '/opt/agent-secret')
def outFile = new File(outDir, nodeName + '.secret')

Thread.start {
    for (int attempt = 0; attempt < 150; attempt++) {
        try {
            def computer = Jenkins.get().getComputer(nodeName)
            if (computer instanceof SlaveComputer) {
                def mac = computer.getJnlpMac()
                if (mac) {
                    outDir.mkdirs()
                    outFile.text = mac + '\n'
                    outFile.setReadable(false, false)
                    outFile.setReadable(true, true)
                    outFile.setWritable(false, false)
                    outFile.setWritable(true, true)
                    println "[init] published the agent secret for ${nodeName}"
                    return
                }
            }
        } catch (Exception e) {
            println "[init] agent secret publish attempt ${attempt} failed: ${e.message}"
        }
        sleep(2000)
    }
    println "[init] WARNING: node ${nodeName} never appeared; no secret published"
}
