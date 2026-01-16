import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  const port = process.env.PORT || 8080;
  await app.listen(port);
  console.log('Gateway running on http://localhost:3003');
}
bootstrap().catch((err) => {
  console.error('App startup error:', err);
});
