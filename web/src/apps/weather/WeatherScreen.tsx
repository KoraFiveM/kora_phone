import { CloudSun,Sun } from 'lucide-react';
import { api } from '../../api';
import { DotClock,Row } from '../../components';
import { LoadState,useLoad } from '../../core/PhoneContext';

export function WeatherScreen() {
  const weather = useLoad(() => api('weather', {}), []);
  return <><LoadState {...weather} retry={weather.refresh} />{weather.value && <div className="weather-screen"><p className="section-label">LOS SANTOS / RIGHT NOW</p>{weather.value.rain > 0 ? <CloudSun size={105} strokeWidth={0.8} /> : <Sun size={105} strokeWidth={0.8} />}<h2>{({ EXTRASUNNY: 'Extra sunny', CLEAR: 'Clear skies', CLOUDS: 'Cloudy', OVERCAST: 'Overcast', RAIN: 'Rain', THUNDER: 'Thunderstorms', SMOG: 'Smog', FOGGY: 'Fog', CLEARING: 'Clearing up', NEUTRAL: 'Calm', SNOW: 'Snow', BLIZZARD: 'Blizzard', SNOWLIGHT: 'Light snow', XMAS: 'Snow', HALLOWEEN: 'Eerie' } as Record<string, string>)[weather.value.condition] || weather.value.condition.toLowerCase()}</h2><p>A little perspective on your day.</p><div className="weather-time"><small>IN-GAME TIME</small><DotClock value={`${String(weather.value.hour).padStart(2, '0')}:${String(weather.value.minute).padStart(2, '0')}`} /></div><Row title="Rain intensity" detail="Current world conditions" end={<strong>{Math.round(weather.value.rain * 100)}%</strong>} /><button className="text-button" onClick={weather.refresh}>Refresh conditions</button></div>}</>;
}
