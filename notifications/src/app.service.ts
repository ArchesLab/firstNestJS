import { Injectable, NotFoundException } from '@nestjs/common';
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
  getHello(): string {
    return 'Hello World!';
  }

  private readonly eventsBaseUrl = 'http://localhost:3002';
  private readonly usersBaseUrl = 'http://localhost:3005';

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
