import groovy.json.JsonGenerator
import groovy.json.JsonGenerator.Converter

nextflow.enable.dsl=2

// comes from nf-test to store json files
params.nf_test_output  = ""

// include dependencies


// include test workflow
include { CLASSIFY_CLUSTERS } from '/Users/andreassjodin/Code/NanoPulse/subworkflows/local/classify_clusters/tests/../main.nf'

// define custom rules for JSON that will be generated.
def jsonOutput =
    new JsonGenerator.Options()
        .addConverter(Path) { value -> value.toAbsolutePath().toString() } // Custom converter for Path. Only filename
        .build()

def jsonWorkflowOutput = new JsonGenerator.Options().excludeNulls().build()

workflow {

    // run dependencies
    

    // workflow mapping
    def input = []
    
                input[0] = Channel.of([
                    [ id:'test', cluster_id:'0' ],
                    file(params.test_data['nanopore']['consensus']['consensus_fasta'], checkIfExists: true)
                ])
                input[1] = Channel.empty()  // kraken2_db
                input[2] = Channel.empty()  // blast_db
                input[3] = Channel.empty()  // blast_tax_db
                input[4] = Channel.empty()  // fastani_refs
                
    //----

    //run workflow
    CLASSIFY_CLUSTERS(*input)
    
    if (CLASSIFY_CLUSTERS.output){

        // consumes all named output channels and stores items in a json file
        for (def name in CLASSIFY_CLUSTERS.out.getNames()) {
            serializeChannel(name, CLASSIFY_CLUSTERS.out.getProperty(name), jsonOutput)
        }	  
    
        // consumes all unnamed output channels and stores items in a json file
        def array = CLASSIFY_CLUSTERS.out as Object[]
        for (def i = 0; i < array.length ; i++) {
            serializeChannel(i, array[i], jsonOutput)
        }    	

    }
}


def serializeChannel(name, channel, jsonOutput) {
    def _name = name
    def list = [ ]
    channel.subscribe(
        onNext: {
            list.add(it)
        },
        onComplete: {
              def map = new HashMap()
              map[_name] = list
              def filename = "${params.nf_test_output}/output_${_name}.json"
              new File(filename).text = jsonOutput.toJson(map)		  		
        } 
    )
}


workflow.onComplete {

    def result = [
        success: workflow.success,
        exitStatus: workflow.exitStatus,
        errorMessage: workflow.errorMessage,
        errorReport: workflow.errorReport
    ]
    new File("${params.nf_test_output}/workflow.json").text = jsonWorkflowOutput.toJson(result)
    
}
