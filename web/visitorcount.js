async function fetchVisitorCount() {
    const apiUrl = 'https://c73lqaarr4.execute-api.us-east-1.amazonaws.com/prod/visitorcount';
    try {
        const response = await fetch(apiUrl, { mode: 'cors' });
        if (!response.ok) {
            throw new Error('Network response was not ok');
        }
        const data = await response.json();
        document.getElementById('visitorCount').textContent = data.visitorCount;
    } catch (error) {
        console.error('Error fetching visitor count:', error);
        document.getElementById('visitorCount').textContent = 'Unavailable';
    }
}

fetchVisitorCount();