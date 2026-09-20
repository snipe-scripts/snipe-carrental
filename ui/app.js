const creator = document.getElementById('creator');
const rental = document.getElementById('rental');
const toast = document.getElementById('toast');
const stationName = document.getElementById('station-name');
const stationVariant = document.getElementById('station-variant');
const stripColor = document.getElementById('strip-color');
const stationPicker = document.getElementById('station-picker');
const stationCount = document.getElementById('station-count');
const stationMeta = document.getElementById('station-meta');
const creatorVehicles = document.getElementById('creator-vehicles');
const catalogModel = document.getElementById('catalog-model');
const catalogLabel = document.getElementById('catalog-label');
const catalogPrice = document.getElementById('catalog-price');
const saveVehicleButton = document.querySelector('[data-save-vehicle]');
const captureButton = document.querySelector('[data-capture]');
const vehicleList = document.getElementById('vehicle-list');

const state = {
    mode: null,
    step: 1,
    station: null,
    stations: [],
    color: '#17d7c4',
    editingVehicleId: null,
    vehicles: [],
    selectedVehicle: 0,
    payment: 'cash',
    duiInput: false,
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

function setMode(mode) {
    state.mode = mode;
    creator.hidden = mode !== 'creator';
    rental.hidden = mode !== 'rental';
}

function closeUi() {
    setMode(null);
    post('close');
}

function showToast(message) {
    toast.textContent = String(message);
    toast.hidden = false;
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => { toast.hidden = true; }, 2800);
}

function setStep(step) {
    state.step = Number(step) || 1;
    document.querySelectorAll('[data-step]').forEach((button) => {
        button.classList.toggle('active', Number(button.dataset.step) === state.step);
    });
    document.querySelectorAll('[data-panel]').forEach((panel) => {
        panel.classList.toggle('active', Number(panel.dataset.panel) === state.step);
    });
}

function selectedVehicle() {
    return state.vehicles[state.selectedVehicle] || state.vehicles[0] || {
        model: 'vehicle', label: 'Rental vehicle', price: 0,
    };
}

function renderRental() {
    const vehicle = selectedVehicle();
    document.getElementById('rental-station-name').textContent = state.station?.label || 'Vehicle rental';
    document.getElementById('vehicle-name').textContent = vehicle.label || vehicle.model || 'Rental vehicle';
    document.getElementById('vehicle-class').textContent = (vehicle.category || vehicle.class || vehicle.model || 'Vehicle').toUpperCase();
    document.getElementById('vehicle-rate').textContent = money(vehicle.price);
    document.getElementById('total-due').textContent = money(vehicle.price);

    vehicleList.replaceChildren(...state.vehicles.map((item, index) => {
        const button = document.createElement('button');
        const label = document.createElement('b');
        const price = document.createElement('small');
        button.type = 'button';
        button.className = `vehicle-option${index === state.selectedVehicle ? ' selected' : ''}`;
        label.textContent = item.label || item.model;
        price.textContent = money(item.price);
        button.append(label, price);
        button.addEventListener('click', () => { state.selectedVehicle = index; renderRental(); });
        return button;
    }));
}

function readStation() {
    return {
        ...(state.station || {}),
        label: stationName.value.trim() || 'New station',
        variant: 'tablet',
        color: state.color,
        vehicles: state.station?.vehicles || [],
    };
}

function renderStationPicker(selectedId = state.station?.id) {
    const blank = document.createElement('option');
    blank.value = '';
    blank.textContent = 'New station';
    const options = state.stations.map((station) => {
        const option = document.createElement('option');
        option.value = String(station.id || '');
        option.textContent = station.label || station.id || 'Unnamed station';
        return option;
    });
    stationPicker.replaceChildren(blank, ...options);
    stationPicker.value = selectedId ? String(selectedId) : '';
    stationCount.textContent = `${state.stations.length} SAVED`;
    if (state.station?.id) stationMeta.textContent = state.station.id;
    else stationMeta.textContent = 'Unsaved station';
}

function clearVehicleEditor() {
    state.editingVehicleId = null;
    catalogModel.value = '';
    catalogLabel.value = '';
    catalogPrice.value = '250';
    saveVehicleButton.textContent = 'ADD VEHICLE';
}

function fillVehicleEditor(vehicle) {
    state.editingVehicleId = vehicle.id || vehicle.model;
    catalogModel.value = vehicle.model || '';
    catalogLabel.value = vehicle.label || '';
    catalogPrice.value = vehicle.price || 250;
    saveVehicleButton.textContent = 'UPDATE VEHICLE';
}

function vehicleFormData() {
    return {
        id: state.editingVehicleId || undefined,
        model: catalogModel.value.trim().toLowerCase(),
        label: catalogLabel.value.trim(),
        price: Math.max(0, Math.round(Number(catalogPrice.value) || 0)),
    };
}

function renderCreator() {
    const station = state.station || {};
    const vehicles = station.vehicles || [];
    const platformReady = Boolean(station.platform);
    const terminalReady = Boolean(station.coords);
    const platformStatus = document.getElementById('platform-status');
    const terminalStatus = document.getElementById('terminal-status');
    platformStatus.textContent = platformReady ? 'PLACED' : 'NOT PLACED';
    terminalStatus.textContent = terminalReady ? 'PLACED' : 'NOT PLACED';
    platformStatus.classList.toggle('ready', platformReady);
    terminalStatus.classList.toggle('ready', terminalReady);
    document.getElementById('save-summary').textContent = platformReady && terminalReady
        ? `${vehicles.length} vehicle${vehicles.length === 1 ? '' : 's'} configured`
        : 'Place the platform and terminal to save.';
    captureButton.disabled = !platformReady;

    creatorVehicles.replaceChildren();
    if (!vehicles.length) {
        const empty = document.createElement('p');
        empty.textContent = 'No vehicles added yet.';
        creatorVehicles.append(empty);
    } else {
        vehicles.forEach((vehicle) => {
            const row = document.createElement('div');
            const info = document.createElement('div');
            const label = document.createElement('b');
            const details = document.createElement('small');
            const actions = document.createElement('div');
            const edit = document.createElement('button');
            const remove = document.createElement('button');
            row.className = 'creator-vehicle';
            label.textContent = vehicle.label || vehicle.model;
            details.textContent = `${vehicle.model} · ${money(vehicle.price)}`;
            info.append(label, details);
            actions.className = 'creator-vehicle-actions';
            edit.type = 'button';
            edit.textContent = 'EDIT';
            edit.addEventListener('click', () => fillVehicleEditor(vehicle));
            remove.type = 'button';
            remove.textContent = 'REMOVE';
            remove.addEventListener('click', () => removeCatalogVehicle(vehicle));
            actions.append(edit, remove);
            row.append(info, actions);
            creatorVehicles.append(row);
        });
    }
}

function populateCreator(station = {}) {
    state.station = station;
    state.color = station.color || '#17d7c4';
    stationName.value = station.label || 'New station';
    stationVariant.value = 'tablet';
    stripColor.value = state.color;
    document.querySelectorAll('[data-color]').forEach((button) => {
        button.classList.toggle('selected', button.dataset.color.toLowerCase() === state.color.toLowerCase());
    });
    clearVehicleEditor();
    renderStationPicker(station.id);
    renderCreator();
}

async function removeCatalogVehicle(vehicle) {
    const result = await post('deleteCatalogVehicle', {
        stationId: state.station?.id,
        vehicleId: vehicle.id || vehicle.model,
    });
    if (result?.ok) {
        if (result.station) populateCreator(result.station);
        clearVehicleEditor();
    } else showToast(result?.message || 'Vehicle could not be removed');
}

async function beginWorldPlacement(callback) {
    document.activeElement?.blur();
    setMode(null);
    const result = await post(callback, readStation());
    if (!result?.ok) {
        setMode('creator');
        showToast(result?.message || 'Placement could not start');
    }
}

window.addEventListener('message', ({ data }) => {
    if (!data || !data.action) return;
    if (data.action === 'openCreator') {
        state.stations = data.stations || data.payload?.stations || [];
        populateCreator(data.station || data.payload?.station || {});
        setMode('creator');
    } else if (data.action === 'openRental') {
        state.station = data.station || data.payload?.station || {};
        state.vehicles = data.vehicles || data.payload?.vehicles || state.station.vehicles || [];
        state.selectedVehicle = 0;
        renderRental();
        setMode('rental');
    } else if (data.action === 'stationUpdate') {
        if (data.stations) state.stations = data.stations;
        populateCreator(data.station || {});
    } else if (data.action === 'vehiclesUpdate') {
        if (state.station) state.station.vehicles = data.vehicles || [];
        const saved = state.stations.find((station) => station.id === state.station?.id);
        if (saved) saved.vehicles = data.vehicles || [];
        renderCreator();
    } else if (data.action === 'notify') {
        showToast(data.message || 'Updated');
    } else if (data.action === 'close') {
        setMode(null);
    } else if (data.action === 'duiInput') {
        state.duiInput = data.enabled === true;
    }
});

const duiButton = (button) => button === 2 ? 'right' : button === 1 ? 'middle' : 'left';
window.addEventListener('mousedown', (event) => {
    if (state.duiInput && event.button === 0) {
        event.preventDefault();
        post('duiPointer', { type: 'click', button: duiButton(event.button) });
    }
});
window.addEventListener('contextmenu', (event) => { if (state.duiInput) event.preventDefault(); });
window.addEventListener('wheel', (event) => {
    if (state.duiInput) post('duiPointer', { type: 'wheel', deltaX: event.deltaX, deltaY: event.deltaY });
}, { passive: true });

document.querySelectorAll('[data-close]').forEach((button) => button.addEventListener('click', closeUi));
document.querySelectorAll('[data-step]').forEach((button) => button.addEventListener('click', () => setStep(button.dataset.step)));
document.querySelectorAll('[data-next]').forEach((button) => button.addEventListener('click', () => setStep(button.dataset.next)));
document.querySelectorAll('[data-color]').forEach((button) => button.addEventListener('click', () => {
    state.color = button.dataset.color;
    stripColor.value = state.color;
    document.querySelectorAll('[data-color]').forEach((item) => item.classList.toggle('selected', item === button));
    post('setStripColor', { color: state.color });
}));
stripColor.addEventListener('input', () => {
    state.color = stripColor.value;
    document.querySelectorAll('[data-color]').forEach((button) => button.classList.remove('selected'));
    post('setStripColor', { color: state.color });
});
document.querySelector('[data-place-platform]').addEventListener('click', () => beginWorldPlacement('placePlatform'));
document.querySelector('[data-place-booth]').addEventListener('click', () => beginWorldPlacement('placeBooth'));
document.querySelector('[data-load-station]').addEventListener('click', async () => {
    if (!stationPicker.value) {
        const result = await post('newStation');
        populateCreator(result?.station || {});
        return;
    }
    const result = await post('selectStation', { id: stationPicker.value });
    if (result?.ok) populateCreator(result.station || {});
    else showToast(result?.message || 'Station could not be opened');
});
document.querySelector('[data-new]').addEventListener('click', async () => {
    const result = await post('newStation');
    populateCreator(result?.station || {});
    setStep(1);
});
saveVehicleButton.addEventListener('click', async () => {
    const vehicle = vehicleFormData();
    if (!vehicle.model || !vehicle.label || vehicle.price < 1) {
        showToast('Enter a model, display name and rental price');
        return;
    }
    const result = await post('saveCatalogVehicle', { stationId: state.station?.id, ...vehicle });
    if (result?.ok) {
        if (result.station) state.station = result.station;
        clearVehicleEditor();
        renderCreator();
    } else showToast(result?.message || 'Vehicle could not be saved');
});
captureButton.addEventListener('click', async () => {
    const vehicle = vehicleFormData();
    const result = await post('captureVehicle', { stationId: state.station?.id, ...vehicle });
    if (result?.ok) {
        if (result.station) state.station = result.station;
        clearVehicleEditor();
        renderCreator();
    } else showToast(result?.message || 'Vehicle could not be captured');
});
document.querySelector('[data-clear-vehicle]').addEventListener('click', clearVehicleEditor);
document.querySelector('[data-save]').addEventListener('click', async () => {
    const result = await post('saveStation', readStation());
    if (result?.ok === false) showToast(result.message || 'Station could not be saved');
});
document.querySelectorAll('[data-payment]').forEach((button) => button.addEventListener('click', () => {
    state.payment = button.dataset.payment;
    document.querySelectorAll('[data-payment]').forEach((item) => item.classList.toggle('selected', item === button));
}));
document.getElementById('rent-button').addEventListener('click', async () => {
    const vehicle = selectedVehicle();
    const result = await post('rentVehicle', {
        stationId: state.station?.id,
        vehicleId: vehicle.id,
        model: vehicle.model,
        payment: state.payment,
    });
    if (result?.ok) closeUi();
    else if (result?.message) showToast(result.message);
});
document.addEventListener('keydown', (event) => { if (event.key === 'Escape') closeUi(); });

document.documentElement.classList.remove('nui-loading');

const preview = new URLSearchParams(location.search).get('preview');
if (preview === 'creator') {
    const previewStation = {
        id: 'legion-square', label: 'Legion Square', variant: 'tablet', color: '#17d7c4',
        coords: { x: 215.12, y: -810.22, z: 29.73, w: 158.0 },
        platform: { x: 219.42, y: -808.91, z: 29.73, w: 158.0 },
        vehicles: [
            { id: 'sultan', model: 'sultan', label: 'Sultan', price: 250 },
            { id: 'blista', model: 'blista', label: 'Blista', price: 180 },
        ],
    };
    state.stations = [previewStation];
    populateCreator(previewStation);
    setMode('creator');
} else if (preview === 'rental') {
    state.station = { id: 'preview', label: 'Legion Square' };
    state.vehicles = [
        { id: 'blista', model: 'blista', label: 'Blista', price: 180 },
        { id: 'sultan', model: 'sultan', label: 'Sultan', price: 250 },
        { id: 'faggio', model: 'faggio', label: 'Faggio', price: 90 },
    ];
    state.selectedVehicle = 1;
    renderRental();
    setMode('rental');
}
