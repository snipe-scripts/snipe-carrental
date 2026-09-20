const summary = document.getElementById('summary');
const rental = document.getElementById('rental');
const closeButton = document.getElementById('close');
const toast = document.getElementById('toast');
const rentButton = document.getElementById('rent');

const state = {
    station: null,
    vehicles: [],
    selected: 0,
    payment: 'cash',
    busy: false,
};

const parentResource = typeof GetParentResourceName === 'function'
    ? GetParentResourceName()
    : 'snipe-carrental';

async function post(name, data = {}) {
    const response = await fetch(`https://${parentResource}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data),
    }).catch(() => null);
    if (!response) return null;
    return response.json().catch(() => ({}));
}

function money(value) {
    return `$${Math.max(0, Math.round(Number(value) || 0)).toLocaleString('en-US')}`;
}

function selectedVehicle() {
    return state.vehicles[state.selected] || { id: '', model: 'vehicle', label: 'No vehicles', price: 0 };
}

function showToast(message) {
    toast.textContent = String(message || 'Unable to continue');
    toast.hidden = false;
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => { toast.hidden = true; }, 3200);
}

function applyStation(data) {
    state.station = data.station || {
        id: data.stationId,
        label: data.label,
        color: data.color,
        vehicles: data.vehicles,
    };
    state.vehicles = Array.isArray(data.vehicles) ? data.vehicles : state.station.vehicles || [];
    if (data.color) document.documentElement.style.setProperty('--accent', String(data.color));
}

function renderSummary() {
    const total = state.vehicles.length;
    document.getElementById('summary-station').textContent = String(state.station?.label || 'CAPSULE STATION').toUpperCase();
    document.getElementById('summary-count').textContent = `${total} VEHICLE${total === 1 ? '' : 'S'}`;
    summary.hidden = false;
    rental.hidden = true;
    closeButton.hidden = true;
}

function renderRental() {
    const vehicle = selectedVehicle();
    document.getElementById('rental-station').textContent = String(state.station?.label || 'VEHICLE RENTAL').toUpperCase();
    document.getElementById('vehicle-name').textContent = vehicle.label || vehicle.model || 'Rental vehicle';
    document.getElementById('vehicle-model').textContent = String(vehicle.model || 'vehicle').toUpperCase();
    document.getElementById('vehicle-price').textContent = money(vehicle.price);
    document.getElementById('total').textContent = money(vehicle.price);
    document.getElementById('vehicle-position').textContent = `${state.vehicles.length ? state.selected + 1 : 0} / ${state.vehicles.length}`;
    summary.hidden = true;
    rental.hidden = false;
    closeButton.hidden = false;
}

function choose(offset) {
    if (!state.vehicles.length || state.busy) return;
    state.selected = (state.selected + offset + state.vehicles.length) % state.vehicles.length;
    renderRental();
}

window.addEventListener('message', ({ data }) => {
    if (!data || !data.action) return;
    if (data.action === 'station') {
        applyStation(data);
        state.selected = 0;
        state.busy = false;
        renderSummary();
    } else if (data.action === 'openRental') {
        applyStation(data);
        state.selected = Math.min(state.selected, Math.max(0, state.vehicles.length - 1));
        state.payment = 'cash';
        state.busy = false;
        document.querySelectorAll('[data-payment]').forEach((button) => {
            button.classList.toggle('selected', button.dataset.payment === state.payment);
        });
        renderRental();
    }
});

document.getElementById('previous').addEventListener('click', () => choose(-1));
document.getElementById('next').addEventListener('click', () => choose(1));
document.querySelectorAll('[data-payment]').forEach((button) => button.addEventListener('click', () => {
    if (state.busy) return;
    state.payment = button.dataset.payment;
    document.querySelectorAll('[data-payment]').forEach((item) => item.classList.toggle('selected', item === button));
}));
closeButton.addEventListener('click', () => post('close'));
rentButton.addEventListener('click', async () => {
    if (state.busy || !state.vehicles.length) return;
    const vehicle = selectedVehicle();
    state.busy = true;
    rentButton.disabled = true;
    rentButton.firstChild.textContent = 'PROCESSING ';
    const result = await post('rentVehicle', {
        stationId: state.station?.id,
        vehicleId: vehicle.id,
        model: vehicle.model,
        payment: state.payment,
    });
    state.busy = false;
    rentButton.disabled = false;
    rentButton.firstChild.textContent = 'RENT VEHICLE ';
    if (result?.ok) post('close');
    else showToast(result?.message || 'Rental could not be created');
});

if (new URLSearchParams(location.search).has('preview')) {
    document.documentElement.classList.add('preview');
    applyStation({
        station: { id: 'preview', label: 'Legion Square', color: '#17d7c4' },
        color: '#17d7c4',
        vehicles: [
            { id: 'blista', model: 'blista', label: 'Blista', price: 180 },
            { id: 'sultan', model: 'sultan', label: 'Sultan', price: 250 },
            { id: 'baller', model: 'baller', label: 'Baller', price: 400 },
        ],
    });
    if (new URLSearchParams(location.search).get('preview') === 'rental') renderRental();
    else renderSummary();
}
