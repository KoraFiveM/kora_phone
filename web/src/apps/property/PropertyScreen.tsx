import { Home,Navigation } from 'lucide-react';
import { api } from '../../api';
import { Empty } from '../../components';
import { LoadState,useLoad,usePhone } from '../../core/PhoneContext';
import type { Property } from '../../types';
import { asList } from '../../types';

export function PropertyScreen() {
  const { run, notify } = usePhone();
  const properties = useLoad(() => api('property', {}), []);
  return <><LoadState {...properties} retry={properties.refresh} />{asList<Property>(properties.value).map(property => <section className="property-card" key={property.name}><div className="property-art"><Home size={58} strokeWidth={1} /><span>HOME / YOUR SPACE</span></div><h3>{property.label || property.name}</h3><p>Owned by your current character</p>{property.coords && <button className="primary" onClick={() => run(async () => { await api('waypoint', property.coords!); notify('Home waypoint selected'); })}><Navigation size={16} />Take me home</button>}</section>)}{!properties.loading && !asList(properties.value).length && <Empty title="Find your place" detail="Properties you own will appear here." />}</>;
}
