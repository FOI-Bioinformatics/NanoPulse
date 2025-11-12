import groovy.json.JsonGenerator
import groovy.json.JsonGenerator.Converter

nextflow.enable.dsl=2

// comes from nf-test to store json files
params.nf_test_output  = ""

// include dependencies


// include test workflow
include { PER_CLUSTER_ASSEMBLY } from '/Users/andreassjodin/Code/NanoPulse/subworkflows/local/per_cluster_assembly/tests/../main.nf'

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
    
                ch_cluster_reads = Channel.of(
                    [
                        [ id:'sample1', cluster_id:'5', single_end:true ],
                        file(params.test_data['nanopore']['reads']['cluster_fastq'], checkIfExists: true)
                    ]
                )

                input[0] = ch_cluster_reads
                input[1] = "1.8k"                  // Different genome size
                input[2] = 50                      // Fewer polishing reads
                input[3] = 2                       // Fewer racon rounds
                input[4] = "r941_min_sup_g507"     // Different medaka model
                
    //----

    //run workflow
    PER_CLUSTER_ASSEMBLY(*input)
    
    if (PER_CLUSTER_ASSEMBLY.output){

        // consumes all named output channels and stores items in a json file
        for (def name in PER_CLUSTER_ASSEMBLY.out.getNames()) {
            serializeChannel(name, PER_CLUSTER_ASSEMBLY.out.getProperty(name), jsonOutput)
        }	  
    
        // consumes all unnamed output channels and stores items in a json file
        def array = PER_CLUSTER_ASSEMBLY.out as Object[]
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
