function loadCharts() {
  loadRatingCharts();
  loadComparisonCharts();
  loadHofCharts();
}

function loadRatingCharts() {
  const ratings = document.getElementsByClassName("ratings")[0];

  const maxValue = Math.max(...Object.values(gon.chartData.ratings)
      .map(data => Math.max(...Object.values(data.ratings))));
  Object.entries(gon.chartData.ratings).forEach(([faceCode, data]) => {
    const rating = createChart(faceCode, data, maxValue);
    ratings.appendChild(rating);
  });
}

function loadComparisonCharts() {
}

function loadHofCharts() {
}

function createChart(faceCode, data, maxValue)  {
  const rating = document.createElement('div');
  rating.className = 'rating';

  const infoDiv = document.createElement('div');
  rating.appendChild(infoDiv);
  infoDiv.className = 'info-section';

  const title = document.createElement('h4');
  infoDiv.appendChild(title);
  title.textContent = `#${faceCode}`;
  title.className = "title";

  const responsesDiv = document.createElement('div');
  responsesDiv.textContent = `Responses: ${data.responses}`;
  responsesDiv.className = 'sub-title';
  infoDiv.appendChild(responsesDiv);

  const avgDiv = document.createElement('div');
  avgDiv.textContent = `Avg: ${data.avg.toFixed(2)}`;
  avgDiv.className = 'sub-title';
  infoDiv.appendChild(avgDiv);

  const weightedDiv = document.createElement('div');
  weightedDiv.textContent = `Baseball's top weighted: ${data.baseballsTopWeighted.toFixed(2)}`;
  weightedDiv.className = 'sub-title';
  infoDiv.appendChild(weightedDiv);

  const image = document.createElement('img');
  infoDiv.appendChild(image);
  image.className = "comment-face-image";
  image.src = gon.commentFaceLinks[faceCode];
  image.alt = `#${faceCode};`

  const chartWrapper = document.createElement('div');
  rating.appendChild(chartWrapper);
  chartWrapper.className = "chart-wrapper";

  const canvas = document.createElement('canvas');
  chartWrapper.appendChild(canvas);

  new Chart(canvas.getContext('2d'), {
    type: 'bar', data: {
      datasets: [{
        label: 'Rating count', data: data.ratings, backgroundColor: backgroundColors(data.ratings)
      }]
    }, options: {
      responsive: true, maintainAspectRatio: false, scales: {
        y: {
          beginAtZero: true, max: maxValue
        }
      }, plugins: {
        legend: {
          display: false
        }, title: {
          display: false
        }
      },
    }
  });

  return rating;
}

function backgroundColors(ratings) {
  const maxIndex = Object.keys(ratings).length - 1;

  return Object.keys(ratings).map((_, i) => {
    const ratio = i / maxIndex;        // 0 to 1
    const hue = (120 * ratio);     // red to green
    return `hsl(${hue}, 70%, 50%)`;
  });
}

document.addEventListener("DOMContentLoaded", function () {
  const debug = document.getElementById("debug")
  if (debug) {
    debug.textContent = JSON.stringify(gon, null, 2);
  }

  if (document.querySelector('.survey .show')) {
    loadCharts();
  }
});
