import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  EMAIL_TEMPLATES,
  type EmailTemplate,
} from './stubs/email-templates.stub';
import axios from 'axios';

@Injectable()
export class AppService {
  private readonly notificationsBaseUrl: string;
  private readonly clubsBaseUrl: string;

  constructor(private readonly configService: ConfigService) {
    const notificationsURL = this.configService.get<string>(
      'NOTIFICATIONS_SERVICE_URL',
    );
    const clubsURL = this.configService.get<string>('CLUBS_SERVICE_URL');
    if (!notificationsURL || !clubsURL) {
      throw new Error(
        'Critical Environment Variable NOTIFICATIONS_SERVICE_URL is missing!',
      );
    }
    this.notificationsBaseUrl = notificationsURL;
    this.clubsBaseUrl = clubsURL;
  }

  getHello(): string {
    return 'Hello World!';
  }

  getEmailTemplate(key: string): EmailTemplate {
    const tpl = EMAIL_TEMPLATES[key];
    if (!tpl) {
      throw new NotFoundException(`Email template not found: ${key}`);
    }
    return tpl;
  }

  async callEventDetailsNotif(eventId: string): Promise<{ message: string }> {
    const url = `${this.notificationsBaseUrl}/notifications/event-update`;
    // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
    const { data } = await axios.post(url);
    return {
      message: `Notifies when ${eventId} details has been modified: ${data}`,
    };
  }

  private events: Array<{ id: number; clubId: number; title: string }> = [];

  createEvent(payload: { clubId: number; title: string }) {
    const id = this.events.length + 1;
    const event = { id, clubId: payload.clubId, title: payload.title };
    this.events.push(event);
    return event;
  }

  async deleteEvent(eventId: string): Promise<{
    eventDeleted: boolean;
    clubsUpdated: boolean;
    eventId: string;
  }> {
    // Simulate internal deletion (no persistence layer yet)
    const eventDeleted = true;
    let clubsUpdated = false;
    const url = `${this.clubsBaseUrl}/clubs/event-reference/${eventId}`;
    await axios.delete(url);
    clubsUpdated = true;
    return { eventDeleted, clubsUpdated, eventId };
  }
}
