public class NumbersToWordsClass {
	public string wordText{set;get;}

      public string convert() {
      wordText=convert(numberval);
      return null;
      }
  

  public long numberval { get; set; }

   public String[] units = new String[]{'Zero ','One ','Two ','Three ','Four ','Five ','Six ','Seven ','Eight ','Nine ','Ten ','Eleven ','Twelve ','Thirteen ','Fourteen ','Fifteen ',
                                        'Sixteen ','Seventeen ','Eighteen ','Nineteen '};
                                        
    public String[] tens = new String[]{'','','Twenty','Thirty','Forty','Fifty','Sixty','Seventy','Eighty','Ninety'};
  
    //This method is used to convert the integer to words
    public  String convert(long i) {
      //
      if( i < 20)  return units[integer.valueOf(i)];
      if( i < 100) return tens[integer.valueOf(i)/10] + ((math.mod(i , 10) > 0)? ' ' + convert(math.mod(i , 10)):'');
      if( i < 1000) return units[integer.valueOf(i)/100] + ' Hundred ' + ((math.mod(i , 100) > 0)?' ' + convert(math.mod(i , 100)):'');
      if( i < 10000) return units[integer.valueOf(i)/1000] + ' Thousand ' + ((math.mod(i , 1000) > 0)?' ' + convert(math.mod(i , 1000)):'');
      if( i < 100000) return convert(i / 1000) + ' Thousand ' + ((math.mod(i , 1000) > 0)? ' ' + convert(math.mod(i ,1000)):'') ;
      if( i < 1000000) return units[integer.valueOf(i)/100000] + ' Lakh ' + ((math.mod(i , 100000) > 0)? ' ' + convert(math.mod(i ,100000)):'') ;
      if( i < 10000000) return convert(i / 100000) + ' Lakh ' + ((math.mod(i , 100000) > 0)? ' ' + convert(math.mod(i ,100000)):'') ;
      if( i < 100000000) return units[integer.valueOf(i)/10000000] + ' Crore ' + ((math.mod(i , 10000000) > 0)? ' ' + convert(math.mod(i , 10000000)):'') ;
      if( i < 1000000000) return convert(i / 10000000) + 'Crore ' + ((math.mod(i , 10000000) > 0)? ' ' + convert(math.mod(i , 10000000)):'') ;
      
      return convert(i / 1000000000) + ' Crore ' + ((math.mod(i , 1000000000) > 0) ? '' + convert(math.mod(i , 1000000000)):'') ;
    }
}