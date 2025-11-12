import groovy.json.JsonGenerator
import groovy.json.JsonGenerator.Converter

nextflow.enable.dsl=2


// comes from testflight to find json files
params.nf_test_output  = ""

// function mapping
def input = []

                input[0] = [
                    file(params.modules_testdata_base_path + '/generic/tsv/test.tsv', checkIfExists: true),
                    file(params.modules_testdata_base_path + '/generic/tsv/network.tsv', checkIfExists: true),
                    file(params.modules_testdata_base_path + '/generic/tsv/expression.tsv', checkIfExists: true)
                ]
                
//----

// include function

include { getSingleReport } from '/Users/andreassjodin/Code/NanoPulse/subworkflows/nf-core/utils_nfcore_pipeline/tests/../main.nf'


// define custom rules for JSON that will be generated.
def jsonOutput =
    new JsonGenerator.Options()
        .addConverter(Path) { value -> value.toAbsolutePath().toString() } // Custom converter for Path. Only filename
        .build()

def jsonWorkflowOutput = new JsonGenerator.Options().excludeNulls().build()


workflow {

  result = getSingleReport(*input)
  if (result != null) {
  	new File("${params.nf_test_output}/function.json").text = jsonOutput.toJson(result)
  }
  
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