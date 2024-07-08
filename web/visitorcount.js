async function fetchVisitorCount() {
    const apiUrl = 'YOUR_API_GATEWAY_ENDPOINT_URL';
    try {
        const response = await fetch(apiUrl);
        const data = await response.json();
        document.getElementById('visitorCount').textContent = data.visitorCount;
    } catch (error) {
        console.error('Error fetching visitor count:', error);
        document.getElementById('visitorCount').textContent = 'Unavailable';
    }
}

fetchVisitorCount();