import groovy.json.JsonGenerator
import groovy.json.JsonGenerator.Converter

nextflow.enable.dsl=2

// comes from nf-test to store json files
params.nf_test_output  = ""

// include dependencies


// include test process
include { JOINCONSENSUS } from '/Users/andreassjodin/Code/NanoPulse/modules/local/joinconsensus/tests/../main.nf'

// define custom rules for JSON that will be generated.
def jsonOutput =
    new JsonGenerator.Options()
        .addConverter(Path) { value -> value.toAbsolutePath().toString() } // Custom converter for Path. Only filename
        .build()

def jsonWorkflowOutput = new JsonGenerator.Options().excludeNulls().build()


workflow {

    // run dependencies
    

    // process mapping
    def input = []
    
                input[0] = [
                    [ id:'test_multi', single_end:true ],
                    [
                        file(params.test_data['nanopore']['consensus']['cluster_0_consensus'], checkIfExists: true),
                        file(params.test_data['nanopore']['consensus']['cluster_1_consensus'], checkIfExists: true),
                        file(params.test_data['nanopore']['consensus']['cluster_2_consensus'], checkIfExists: true)
                    ],
                    [
                        file(params.test_data['classification']['classification_json'], checkIfExists: true),
                        file(params.test_data['classification']['classification_cluster0'], checkIfExists: true),
                        file(params.test_data['classification']['classification_cluster1'], checkIfExists: true)
                    ]
                ]
                
    //----

    //run process
    JOINCONSENSUS(*input)

    if (JOINCONSENSUS.output){

        // consumes all named output channels and stores items in a json file
        for (def name in JOINCONSENSUS.out.getNames()) {
            serializeChannel(name, JOINCONSENSUS.out.getProperty(name), jsonOutput)
        }	  
      
        // consumes all unnamed output channels and stores items in a json file
        def array = JOINCONSENSUS.out as Object[]
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
