import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import axios from 'axios';

type EmailTemplate = {
  key: string;
  subject: string;
  html: string;
  text: string;
  variables: string[];
};

@Injectable()
export class AppService {
  private readonly eventsBaseUrl: string;
  private readonly usersBaseUrl: string;

  constructor(private readonly configService: ConfigService) {
    const eventsURL = this.configService.get<string>('EVENTS_SERVICE_URL');
    const usersURL = this.configService.get<string>('USERS_SERVICE_URL');
    if (!eventsURL || !usersURL) {
      throw new Error(
        'Critical Environment Variable EVENTS_SERVICE_URL or USERS_SERVICE_URL is missing!',
      );
    }
    this.eventsBaseUrl = eventsURL;
    this.usersBaseUrl = usersURL;
  }

  getHello(): string {
    return 'Hello World!';
  }

  async fetchTemplate(templateId: string): Promise<EmailTemplate> {
    const url = `${this.eventsBaseUrl}/events/template-data/${templateId}`;
    const { data } = await axios.get<EmailTemplate>(url);
    if (!data) {
      throw new NotFoundException(
        `Template ${templateId} not found in Events service.`,
      );
    }
    return data;
  }

  async unsubscribeUser(userId: string): Promise<{ message: string }> {
    const url = `${this.usersBaseUrl}/users/unsubscribe/${userId}`;
    const { data } = await axios.patch<{ message: string }>(url);
    return data;
  }
}
