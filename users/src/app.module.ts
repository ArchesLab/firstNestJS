import { Module } from '@nestjs/common';
import { HttpModule } from '@nestjs/axios';
import { UsersController } from './app.controller';
import { UsersService } from './users.service';
import { ClubsClientService } from './clubs-client.service';

@Module({
  imports: [HttpModule],
  controllers: [UsersController],
  providers: [UsersService, ClubsClientService],
})
export class AppModule {}
