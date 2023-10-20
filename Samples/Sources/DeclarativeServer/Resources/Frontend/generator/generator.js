function RequestUUID(outputID) {
    var outputElement = document.getElementById(outputID);

    var httpRequest = false;

    if (window.XMLHttpRequest) { // Mozilla, Safari, ...
        httpRequest = new XMLHttpRequest();
        if (httpRequest.overrideMimeType) {
            httpRequest.overrideMimeType('text/plain');
        }
    } else if (window.ActiveXObject) { // IE
        try {
            httpRequest = new ActiveXObject('Msxml2.XMLHTTP');
        } catch (e) {
            try {
                httpRequest = new ActiveXObject('Microsoft.XMLHTTP');
            } catch (e) { }
        }
    }

    if (!httpRequest) {
        alert('Failed to create a request');
        return;
    }
    httpRequest.open('GET', 'https://' + window.location.host + '/generate/uuid?string', true);
    httpRequest.send(null);

    httpRequest.onreadystatechange = function() {
        if (httpRequest.readyState != 4) { return; }

        switch (httpRequest.status) {
        case 200:
            outputElement.innerText = httpRequest.responseText;
            break;
        default:
            outputElement.innerText = 'Response status ' + httpRequest.status;
            break;
        }
    };
}


function RandomColor(outputID) {
    var r = Math.floor(256 * Math.random());
    var g = Math.floor(256 * Math.random());
    var b = Math.floor(256 * Math.random());

    document.getElementById(outputID).innerText = 'rgb(' + r + ', ' + g + ', ' + b + ')';
}
