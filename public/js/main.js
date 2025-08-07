function loadCharts() {
  autoSelectTab();
  loadRatingCharts();
  loadComparisonCharts();
  loadHofCharts();
}

function autoSelectTab() {
  const hash = window.location.hash || gon.defaultTab;

  selectTab(hash);

  document.querySelectorAll('a[data-bs-toggle="tab"]').forEach(tab => {
    tab.addEventListener('shown.bs.tab', function (e) {
      const href = e.target.getAttribute('href');
      if (window.location.hash !== href) {
        history.pushState({tab: href}, "", href);
      } else {
        history.replaceState({tab: href}, "", href);
      }
    });
  });

  // Handle browser back/forward buttons
  window.addEventListener('popstate', (e) => {
    if (e.state && e.state.tab) {
      selectTab(e.state.tab);
    }
  });

  // Push default tab into URL if no hash is present
  if (!window.location.hash) {
    history.replaceState({tab: hash}, "", hash);
  }
}

function selectTab(hash) {
  const tabTrigger = document.querySelector(`a[href="${hash}"]`);
  if (tabTrigger) {
    const tab = new bootstrap.Tab(tabTrigger);
    tab.show();
  }
}

function loadRatingCharts() {
  const ratings = document.getElementsByClassName("ratings")[0];

  const maxValue = Math.max(...Object.values(gon.chartData.ratings)
      .map(data => Math.max(...Object.values(data.ratings))));
  Object.entries(gon.chartData.ratings).forEach(([faceCode, data]) => {
    const chart = createChart('rating', faceCode, data, maxValue);
    ratings.appendChild(chart);
  });
}

function loadComparisonCharts() {
}

function loadHofCharts() {
  const hofs = document.getElementsByClassName("hall-of-fames")[0];

  const maxValue = Math.max(...Object.values(gon.chartData.hof)
      .map(data => Math.max(...Object.values(data.ratings))));
  Object.entries(gon.chartData.hof).forEach(([faceCode, data]) => {
    const chart = createChart('hall-of-fame', faceCode, data, maxValue);
    hofs.appendChild(chart);
  });
}

function createChart(className, faceCode, data, maxValue) {
  const rating = document.createElement('div');
  rating.className = className;

  const infoDiv = document.createElement('div');
  rating.appendChild(infoDiv);
  infoDiv.className = 'info-section';

  const title = document.createElement('h4');
  infoDiv.appendChild(title);
  title.textContent = `#${faceCode}`;
  title.className = "title";
  rating.setAttribute('data-name', faceCode);

  const responsesDiv = document.createElement('div');
  responsesDiv.textContent = `Responses: ${data.responses}`;
  responsesDiv.className = 'sub-title';
  infoDiv.appendChild(responsesDiv);

  if (data.hasOwnProperty('score')) {
    const scoreDiv = document.createElement('div');
    scoreDiv.textContent = `Score: ${data.score}`;
    scoreDiv.className = 'sub-title';
    infoDiv.appendChild(scoreDiv);
    rating.setAttribute('data-score', data.score);
  }

  if (data.hasOwnProperty('avg')) {
    const avgDiv = document.createElement('div');
    avgDiv.textContent = `Avg: ${data.avg.toFixed(2)}`;
    avgDiv.className = 'sub-title';
    infoDiv.appendChild(avgDiv);
    rating.setAttribute('data-avg', data.avg);
  }

  if (data.hasOwnProperty('baseballsTopWeighted')) {
    const weightedDiv = document.createElement('div');
    weightedDiv.textContent = `Baseball's top weighted: ${data.baseballsTopWeighted.toFixed(2)}`;
    weightedDiv.className = 'sub-title';
    infoDiv.appendChild(weightedDiv);
    rating.setAttribute('data-baseball-top-weighted', data.baseballsTopWeighted);
  }

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
        label: '# Answers', data: data.ratings, backgroundColor: backgroundColors(data.ratings)
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

const sortStates = {}; // Keeps sort state per container
const previousButtons = {}; // Keeps previous button per container

function sortDivs(className, attribute, button, startAscending = false) {
  const container = document.getElementsByClassName(className)[0];
  const items = Array.from(container.children);

  // Set up state for this container if it doesn’t exist yet
  if (!sortStates[className]) {
    sortStates[className] = {key: '', asc: true};
  }

  const state = sortStates[className];

  // Update sort direction
  if (state.key === attribute) {
    state.asc = !state.asc;
  } else {
    state.key = attribute;
    state.asc = startAscending;
  }

  // Sort items
  items.sort((a, b) => {
    let valA = a.getAttribute(`data-${attribute}`);
    let valB = b.getAttribute(`data-${attribute}`);

    if (!isNaN(valA) && !isNaN(valB)) {
      valA = Number(valA);
      valB = Number(valB);
    }

    const comparison = valA > valB ? 1 : valA < valB ? -1 : 0;
    return state.asc ? comparison : -comparison;
  });

  // Reinsert sorted items
  items.forEach(item => container.appendChild(item));

  // Update arrows
  const arrow = state.asc ? '↑' : '↓';
  if (previousButtons[className] && previousButtons[className] !== button) {
    previousButtons[className].querySelector('span').textContent = '';
  }
  button.querySelector('span').textContent = arrow;
  previousButtons[className] = button;
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
