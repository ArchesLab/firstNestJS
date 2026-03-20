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
@Injectable()
export class AppService {
  private readonly notificationsBaseUrl: string;
  private readonly usersServiceBase: string;
  private readonly clubsServiceBase: string;

  constructor(private readonly configService: ConfigService) {
    const notifURL = this.configService.get<string>('NOTIFICATIONS_SERVICE_URL') || '';
    const userURL = this.configService.get<string>('USERS_SERVICE_URL') || '';
    const clubURL = this.configService.get<string>('CLUBS_SERVICE_URL') || '';

     this.notificationsBaseUrl = notifURL;
     this.usersServiceBase = userURL;
     this.clubsServiceBase = clubURL;

    if (!notifURL || !userURL || !clubURL) {
      throw new Error('Required environment variables are missing!');
    }
  }
}
//FAILED - configService url MUST include %SERVICE_URL% in order to be valid
async function test1(configService: ConfigService){
    const input = configService.get('TEMP_URL');
    const response = await axios.get(`${input}/api/data/endpoint`);
}
//PASS - configService url MUST include %SERVICE_URL% in order to be valid
async function test2(configService: ConfigService){
    const input = configService.get('TEMP_SERVICE_URL');
    const response = await axios.get(`${input}/api/data/endpoint`);
}

async function test3(configService: ConfigService){
    const input = configService.get('TEMP_SERVICE_URL');
    const tempURL = input || 'ANOTHER_SERVICE_URL';
    const response = await axios.get(`${tempURL}/api/data/endpoint`);
}

//PASS - included usage of constructor 
export class AppService2 {
    private readonly tempBaseUrl: string;
    constructor(private readonly configService: ConfigService) {
        const tempURL = this.configService.get<string>('TEMP_SERVICE_URL') || '';
        this.tempBaseUrl = tempURL;
    }
    async test4(configService: ConfigService){
        //const input = configService.get('TEMP_SERVICE_URL');
        const response = await axios.get(`${this.tempBaseUrl}/api/data/endpoint`);
    }
}

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
    const input = configService.get('TEMP2_SERVICE_URL');
    const endpoint = `${input}/api/data/${url}`;
    const response = await axios.get(endpoint);
    return response.data;
}
