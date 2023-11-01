#include "fir.h"

void __attribute__ ( ( section ( ".mprjram" ) ) ) initfir() {
	//initial your fir
}

int* __attribute__ ( ( section ( ".mprjram" ) ) ) fir(){
	initfir();
	
	for(int i = 0 ; i < N ; i++){
	    outputsignal[i] = 0;
	    for(int j = 0 ; j < N ; j++){
	        if( i-j >= 0){
	            outputsignal[i] += taps[j] * inputsignal[i-j];
	        }
	    }
	}
	
	//write down your fir
	
	return outputsignal;
}
		
