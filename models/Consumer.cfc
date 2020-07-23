/**
 * This class will implement com.rabbitmq.client.Consumer
 * https://rabbitmq.github.io/rabbitmq-java-client/api/current/com/rabbitmq/client/Consumer.html
 * Interface for application callback objects to receive notifications and messages from a queue by subscription.
 */
component accessors="true"{

	property name="log" inject="logbox:logger:{this}";
	property name="wirebox" inject="wirebox";
	
    /**
     * Constructor
     *
     * @channel RabbitMQ Connection Channel https://rabbitmq.github.io/rabbitmq-java-client/api/current/com/rabbitmq/client/Channel.html
     * @consumerTag The consumer tag associated with the consumer
     */
    function init( required channel, required udf, loadAppContext=true ){
        variables.channel       = arguments.channel;
        variables.consumerTag   = '';
        variables.udf   = udf;

		variables.System          = createObject( "java", "java.lang.System" );
		variables.Thread          = createObject( "java", "java.lang.Thread" );
		variables.UUID            = createUUID();
		variables.oneHundredYears = ( 60 * 60 * 24 * 365 * 100 );
		variables.loadAppContext  = arguments.loadAppContext;

		// If loading App context or not
		if ( arguments.loadAppContext ) {
			if ( server.keyExists( "lucee" ) ) {
				variables.cfContext   = getCFMLContext().getApplicationContext();
				variables.pageContext = getCFMLContext();
			} else {
				variables.fusionContextStatic   = createObject( "java", "coldfusion.filter.FusionContext" );
				variables.originalFusionContext = fusionContextStatic.getCurrent();
				variables.originalPageContext   = getCFMLContext();
				variables.originalPage          = variables.originalPageContext.getPage();
			}
			// out( "==> Storing contexts for thread: #getCurrentThread().toString()#." );
		}

        return this;
    }

    /**
     * No-op implementation of {@link Consumer#handleCancel}.
     * @param consumerTag the defined consumer tag (client- or server-generated)
     */
    public void function handleCancel( String consumerTag ){
        // no work to do
    }

    /**
     * Implementation of {@link Consumer#handleCancelOk}.
     * @param consumerTag the defined consumer tag (client- or server-generated)
     */
    public void function handleCancelOk( String consumerTag ){
		loadContext();
		try {
	        log.info( 'Cancelling RabbitMQ Consumer [#consumerTag#]' );
		} catch( any e ) {
			err( e );
		} finally {
			unLoadContext();
		}
    }

     /**
     * Stores the most recently passed-in consumerTag - semantically, there should be only one.
     * @see Consumer#handleConsumeOk
     */
    public void function handleConsumeOk( String consumerTag ){
		loadContext();
		try {
	        variables.consumerTag = arguments.consumerTag;
	        log.info( 'Starting RabbitMQ Consumer [#consumerTag#]' );
		} catch( any e ) {
			err( e );
		} finally {
			unLoadContext();
		}
    }

     /**
     * No-op implementation of {@link Consumer#handleDelivery}.
     */
    public void function handleDelivery(
        consumerTag,
        envelope,
        properties,
        body
    ){
		loadContext();
		try {
			var message = wirebox.getInstance( 'message@rabbitsdk' )
				.setChannel( channel.getChannel() )
				.setConnection( channel.getConnection() )
				.populate( envelope, properties, body );
				
			var result = udf( message, log );
			
			// Ack/Nack by convention, returning boolean from UDF.
			if( !isNull( local.result ) && isBoolean( local.result ) ) {
				if( local.result ) {
					message.acknowledge();
				} else {
					message.reject();						
				}
			}
		} catch( any e ) {
			try {
				log.error( 'Error in RabbitMQ Consumer [#consumerTag#]', e );
			} catch( any innerE ) {
				err( e );
				err( innerE );
			}
		} finally {
			unLoadContext();
		}
	}

    /**
     * No-op implementation of {@link Consumer#handleRecoverOk}.
     */
    public void function handleRecoverOk(){
        // no work to do
    }

    /**
     * No-op implementation of {@link Consumer#handleShutdownSignal}.
     */
    public void function handleShutdownSignal( String consumerTag, sig ){        
		loadContext();
		try {
	        log.info( 'Shutdown signal received by RabbitMQ Consumer [#consumerTag#]' );
		} catch( any e ) {
			err( e );
		} finally {
			unLoadContext();
		}
    }


	/**
	 * Get the current thread java object
	 */
	function getCurrentThread(){
		return variables.Thread.currentThread();
	}

	/**
	 * Get the current thread name
	 */
	function getThreadName(){
		return getCurrentThread().getName();
	}

	/**
	 * This function is used for the engine to compile the page context bif into the page scope,
	 * if not, we don't get access to it.
	 */
	function getCFMLContext(){
		return getPageContext();
	}

	/**
	 * Ability to load the context into the running thread
	 */
	function loadContext(){
		// Are we loading the context or not?
		if ( !variables.loadAppContext ) {
			return;
		}

		// out( "==> Context NOT loaded for thread: #getCurrentThread().toString()# loading it..." );

		// Lucee vs Adobe Implementations
		if ( server.keyExists( "lucee" ) ) {
			getCFMLContext().setApplicationContext( variables.cfContext );
		} else {
			var fusionContext = variables.originalFusionContext.clone();
			var pageContext   = variables.originalPageContext.clone();
			pageContext.resetLocalScopes();
			var page             = variables.originalPage._clone();
			page.pageContext     = pageContext;
			fusionContext.parent = page;

			variables.fusionContextStatic.setCurrent( fusionContext );
			fusionContext.pageContext = pageContext;
			pageContext.setFusionContext( fusionContext );
			pageContext.initializeWith(
				page,
				pageContext,
				pageContext.getVariableScope()
			);
		}
	}

	/**
	 * Ability to unload the context out of the running thread
	 */
	function unLoadContext(){
		// Are we loading the context or not?
		if ( !variables.loadAppContext ) {
			return;
		}

		// out( "==> Removing context for thread: #getCurrentThread().toString()#." );

		// Lucee vs Adobe Implementations
		if ( server.keyExists( "lucee" ) ) {
			// Nothing right now
		} else {
			variables.fusionContextStatic.setCurrent( javacast( "null", "" ) );
		}
	}

	/**
	 * Utiliy to send to output to console from a runanble
	 *
	 * @var Variable/Message to send
	 */
	function out( required var ){
		variables.System.out.println( arguments.var.toString() );
	}

	/**
	 * Utiliy to send to output to console from a runanble via the error stream
	 *
	 * @var Variable/Message to send
	 */
	function err( required var ){
		variables.System.err.println( arguments.var.toString() );
	}


	/**
	 * Engine-specific lock name. For Adobe, lock is shared for this CFC instance.  On Lucee, it is random (i.e. not locked).
	 * This singlethreading on Adobe is to workaround a thread safety issue in the PageContext that needs fixed.
	 * Ammend this check once Adobe fixes this in a later update
	 */
	function getConcurrentEngineLockName(){
		if ( server.keyExists( "lucee" ) ) {
			return createUUID();
		} else {
			return variables.UUID;
		}
	}
}