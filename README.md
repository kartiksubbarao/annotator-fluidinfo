# annotator-fluidinfo

Fluidinfo backend store for okfn/annotator

## Installation

Make sure that you have the following Perl modules installed (e.g. via
CPAN or system packages):

Mojolicious
Net::Fluidinfo

## Usage

Set up an HTML page with the annotator Store plugin. Here is an example
from the annotator dev.html page:

```
<script>
	var devAnnotator
	(function ($) {
		var elem = document.getElementById('airlock');
		
		devAnnotator = new Annotator(elem)
			.addPlugin('Store', {
				prefix: 'http://localhost:3000',
				loadFromSearch: {
					uri: 'http://localhost/annotator/dev.html'
				},
				annotationData: {
					uri: 'http://localhost/annotator/dev.html'
				}
		});
	}(jQuery));
</script>
```

Set the FLUIDINFO_USERNAME and FLUIDINFO_PASSWORD environment variables
accordingly, and then start the backend:

`annotator-fluidinfo.pl`

By default, the backend runs on port 3000.
