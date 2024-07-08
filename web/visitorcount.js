async function fetchVisitorCount() {
    const apiUrl = 'https://x0h9cpxeti.execute-api.us-east-1.amazonaws.com/prodvisitorcount';
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