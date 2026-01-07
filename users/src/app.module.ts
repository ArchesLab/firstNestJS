import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { HttpModule } from '@nestjs/axios';
import { UsersController } from './app.controller';
import { UsersService } from './users.service';
import { ClubsClientService } from './clubs-client.service';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), HttpModule],
  controllers: [UsersController],
  providers: [UsersService, ClubsClientService],
})
export class AppModule {}
