import { Car,MapPin } from 'lucide-react';
import { api } from '../../api';
import { Empty,Row } from '../../components';
import { LoadState,useLoad } from '../../core/PhoneContext';
import type { Vehicle } from '../../types';
import { asList } from '../../types';

export function VehiclesScreen() {
  const vehicles = useLoad(() => api('vehicles', {}), []);
  return <><LoadState {...vehicles} retry={vehicles.refresh} />{asList<Vehicle>(vehicles.value).map(vehicle => <section className="vehicle-card" key={vehicle.plate}><Car size={72} strokeWidth={1} /><div className="vehicle-heading"><h3>{vehicle.vehicle}</h3><span className="plate">{vehicle.plate}</span></div><div className="vehicle-stats"><div><small>STATUS</small><strong>{vehicle.state === 1 ? 'Garaged' : vehicle.state === 2 ? 'Impounded' : 'Out'}</strong></div><div><small>FUEL</small><strong>{Math.round(vehicle.fuel)}%</strong></div></div><Row title={vehicle.garage || 'Unknown garage'} detail="Last registered garage" icon={<MapPin size={18} />} /></section>)}{!vehicles.loading && !asList(vehicles.value).length && <Empty title="The road is waiting" detail="Your character’s owned vehicles will appear here." />}</>;
}
