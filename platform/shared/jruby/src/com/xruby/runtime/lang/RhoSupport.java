package com.xruby.runtime.lang;

import com.xruby.runtime.builtin.ObjectFactory;
import com.xruby.runtime.builtin.RubyArray;
import com.xruby.runtime.builtin.RubyPlatformUtils;

public class RhoSupport {

	public static RubyModule SystemModule;
	private static String    m_strCurAppPath;
	
	public static void init(){

		RubyRuntime.KernelModule.defineModuleMethod( "eval_compiled_file", new RubyTwoArgMethod(){ 
			protected RubyValue run(RubyValue receiver, RubyValue arg1, RubyValue arg2, RubyBlock block ){
				return eval_compiled_file(receiver, arg1, arg2);}
		});
		RubyRuntime.KernelModule.defineModuleMethod( "__rhoGetCurrentDir", new RubyNoArgMethod(){ 
			protected RubyValue run(RubyValue receiver, RubyBlock block ){
				return RhoGetCurrentDir(receiver);}
		});
		RubyRuntime.KernelModule.defineModuleMethod( "__load_with_reflection__", new RubyOneArgMethod(){ 
			protected RubyValue run(RubyValue receiver, RubyValue arg, RubyBlock block ){
				return loadWithReflection(receiver, arg, block);}
		});
		
		SystemModule = RubyAPI.defineModule("System");
		SystemModule.defineModuleMethod( "get_property", new RubyOneArgMethod(){ 
			protected RubyValue run(RubyValue receiver, RubyValue arg, RubyBlock block ){
				return get_property(receiver, arg);}
		});
		
	}

    public static String createMainClassName(String required_file) {
        //remove ".rb" if has one
        if (required_file.endsWith(".rb")) {
            required_file = required_file.substring(0, required_file.length() - 3);
        }else if (required_file.endsWith(".iseq")) {
            required_file = required_file.substring(0, required_file.length() - 5);
        }

        if ( required_file.charAt(0) == '/' || required_file.charAt(0) == '\\' )
        	required_file = required_file.substring(1);
        
        required_file = required_file.replace('/', '$');
        required_file = required_file.replace('\\', '$');
        required_file += ".main";
        return "xruby." + required_file;
    }

	//@RubyLevelMethod(name="__rhoGetCurrentDir", module=true)
    public static RubyValue RhoGetCurrentDir(RubyValue receiver) {
    	return ObjectFactory.createString("");
    }
    
	public static Class findClass(String path){
		String name = createMainClassName(path);
		Class c = null;
		
		try{
			c = Class.forName(name);
		}catch(ClassNotFoundException exc){}
		
		return c;
	}
    
	//@RubyLevelMethod(name="eval_compiled_file", module=true)
    public static RubyValue eval_compiled_file(RubyValue receiver, RubyValue file, RubyValue bindingArg) {
        RubyBinding binding = null;
        if (bindingArg != null && bindingArg instanceof RubyBinding) {
            binding = (RubyBinding)bindingArg;
        }
    	
    	return evalPrecompiledFile( file.toStr(), binding );
    }
	
	private static RubyValue evalPrecompiledFile( String file_name, RubyBinding binding ){
		String name = createMainClassName(file_name);
        try {
            Class c = Class.forName(name);
            Object o = c.newInstance();
            RubyProgram p = (RubyProgram) o;

            if (null != binding) {
                return p.invoke(binding.getSelf(), binding.getVariables(), binding.getBlock(), binding.getScope());
            } else {
                return p.invoke();
            }
        }
        catch (RubyException e) {
            throw e;
        }
        catch (Exception e) {
            throw new RubyException(e.toString());
        }
	}
    
    //@RubyLevelMethod(name="get_property", module=true)
    public static RubyValue get_property(RubyValue receiver, RubyValue arg) {
    	String strPropName = arg.toStr();
    	if ( strPropName.equalsIgnoreCase("platform") ){
    		
    		String platform = RubyPlatformUtils.getPlatform();
    		if ( platform == null )
    			return ObjectFactory.createString("Blackberry");
    		else
    			return ObjectFactory.createString(platform);
    	}
    	
    	return RubyConstant.QNIL;
    }
    
    //@RubyLevelMethod(name="__load_with_reflection__", module=true)
    public static RubyValue loadWithReflection(RubyValue receiver, RubyValue arg, RubyBlock block) {
        String required_file = arg.toStr();
        String name = RhoSupport.createMainClassName(required_file);
        try {
        	
        	Class c = null;
            try {
            	c = Class.forName(name);
            } catch (ClassNotFoundException e) {
            }
            if ( c == null ){
            	name = RhoSupport.createMainClassName(m_strCurAppPath+required_file);
            	c = Class.forName(name);
            	
            	arg = ObjectFactory.createString(m_strCurAppPath+required_file);
            }
            
            Object o = c.newInstance();
            RubyProgram p = (RubyProgram) o;

            //$".push(file_name) unless $".include?(file_name)
            RubyValue var = GlobalVariables.get("$\"");
            if ( var != RubyConstant.QNIL ){
	            RubyArray a = (RubyArray)var;
	            if (a.include(arg) == RubyConstant.QFALSE) {
	                a.push(arg);
	            }
            }
            
            p.invoke();
            return RubyConstant.QTRUE;
        } catch (ClassNotFoundException e) {
            return RubyConstant.QFALSE;
        } catch (InstantiationException e) {
            return RubyConstant.QFALSE;
        } catch (IllegalAccessException e) {
            return RubyConstant.QFALSE;
        }
    }

	public static void setCurAppPath(String curAppPath) {
		m_strCurAppPath = curAppPath;
	}
    
}
