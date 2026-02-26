import axios from 'axios';
import {
  Injectable,
  BadRequestException,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

// function load_from_some_strange_place() {
//   if (rand()) { 
//       return "CamillaHost"
//   } else 
//       return "TobiasHost"
// }

// if (some_condition) {
//     config_param = "localhost"
// } else {
//     config_param = load_from_some_strange_place()
// }
// url = f"{this.configServie.get<string>(config_param)}://fewfewfrew"

async function load_variable_value(a: number, b: number){
    const sum = a + b;
    if( sum > 10)
        return 'CamillaHost';
    return 'TobiasHost';
}

async function test_function_parameter(configService: ConfigService) {
    const value = false;
    let url: string = '';
    if(value){
        url = 'LocalHost';
    } else{
        url = await load_variable_value(5, 6);
    }
    // Add axios call to test
    const input = configService.get('TEMP_URL');
    const endpoint = `${input}/api/data/${url}`;
    const response = await axios.get(endpoint);
    return response.data;
}
